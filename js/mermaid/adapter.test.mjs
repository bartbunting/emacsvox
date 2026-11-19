// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { project, spokenLabel, MAX_SOURCE_BYTES } from './adapter.mjs';

test('Zabbix example retains labels, directed relationships and dotted annotations', () => {
  const source = readFileSync(new URL('../../test/fixtures/mermaid/zabbix.mmd', import.meta.url), 'utf8');
  const { graph, diagnostics } = project(source);
  assert.deepEqual(diagnostics, []);
  assert.equal(graph.nodes.length, 13);
  assert.equal(graph.edges.length, 15);
  assert.deepEqual(graph.edges.filter(e => e.from === 'G').map(e => e.to), ['H', 'S', 'K']);
  assert.equal(graph.edges.filter(e => e.stroke === 'dotted').length, 3);
  assert.equal(graph.edges.find(e => e.from === 'C').label, 'capture and compare');
});

test('invalid diagrams never expose a recovered partial graph', () => {
  const { graph, diagnostics } = project('flowchart TD\nA --> B\nC[unfinished');
  assert.equal(graph, null);
  assert.ok(diagnostics.some(d => d.severity === 'error' && d.range.start > 0));
  assert.throws(() => project('sequenceDiagram\nA->>B: hello'), /flowcharts only/);
});

test('source positions count Unicode characters and retain original CRLF and front matter', () => {
  const source = '---\r\n title: 😀 sample\r\n---\r\nflowchart LR\r\nA["😀 &amp; text"] --> B[End]\r\n';
  const { graph } = project(source);
  const characters = Array.from(source);
  const b = graph.nodes.find(n => n.id === 'B');
  assert.equal(characters.slice(b.range.start, b.range.end).join(''), 'B');
  assert.equal(b.range.start, characters.indexOf('B'));
  assert.equal(graph.nodes[0].label, '😀 & text');
});

test('chains, cycles, self links and parallel edges retain independent identities', () => {
  const { graph } = project('flowchart TD\nA --> B & C --> D\nD --> A\nA -->|again| B\nA --> A');
  assert.equal(graph.edges.length, 7);
  assert.equal(new Set(graph.edges.map(e => e.id)).size, 7);
  assert.equal(graph.edges.filter(e => e.from === 'A' && e.to === 'B').length, 2);
  assert.ok(graph.edges.some(e => e.from === 'A' && e.to === 'A'));
});

test('undirected, bidirectional, marker-ended and invisible links are distinguished', () => {
  const { graph } = project('flowchart TD\nA --- B\nB <--> C\nC o--o D\nD ~~~ E');
  assert.deepEqual(graph.edges.map(e => e.direction), ['none', 'both', 'none']);
  assert.equal(graph.edges[2].arrow, 'double_arrow_circle');
  assert.equal(graph.hiddenEdges, 1);
  assert.equal(graph.nodes.length, 5);
});

test('nested groups remain navigable objects and valid edge endpoints', () => {
  const { graph } = project('flowchart TD\nsubgraph outer[Outer]\nsubgraph inner[Inner]\nA --> B\nend\nC\nend\nouter --> D');
  const outer = graph.nodes.find(n => n.id === 'outer');
  const inner = graph.nodes.find(n => n.id === 'inner');
  assert.equal(outer.kind, 'group');
  assert.ok(outer.members.includes('inner'));
  assert.ok(inner.members.includes('A'));
  assert.ok(inner.groups.includes('outer'));
  assert.equal(graph.edges[1].from, 'outer');
});

test('duplicate labels preserve identity and redeclarations update spoken labels', () => {
  const { graph } = project('flowchart TD\nA[Same] --> B[Same]\nC[Old]\nC[New]');
  assert.deepEqual(graph.nodes.map(n => [n.id, n.label]), [['A', 'Same'], ['B', 'Same'], ['C', 'New']]);
});

test('accessibility metadata and basic label styling become plain text', () => {
  const { graph } = project('flowchart TD\naccTitle: Example\naccDescr: Explanation\nA["<b>Hello</b><br/>world"]');
  assert.equal(graph.title, 'Example');
  assert.equal(graph.description, 'Explanation');
  assert.equal(graph.nodes[0].label, 'Hello; world');
  assert.equal(spokenLabel('**Bold** and _italic_ &lt;literal&gt;', 'markdown'), 'Bold and italic <literal>');
});

test('size and parser limits fail explicitly instead of silently dropping elements', () => {
  assert.throws(() => project('x'.repeat(MAX_SOURCE_BYTES + 1)), /256 KiB/);
  const result = project('flowchart TD\n' + Array.from({ length: 1001 }, (_, i) => `N${i}`).join('\n'));
  assert.equal(result.graph, null);
  assert.ok(result.diagnostics.some(d => d.severity === 'error'));
});

test('persistent helper correlates replies and survives invalid input', () => {
  const requests = [
    '{broken',
    JSON.stringify({ schema: 1, id: 7, source: 'flowchart TD\nA --> B' }),
    JSON.stringify({ schema: 1, id: 8, source: 'flowchart TD\nC --> D' }),
  ].join('\n') + '\n';
  const result = spawnSync(process.execPath, [new URL('server.mjs', import.meta.url).pathname],
    { input: requests, encoding: 'utf8', timeout: 10000 });
  assert.equal(result.status, 0, result.stderr);
  const replies = result.stdout.trim().split('\n').map(JSON.parse);
  assert.ok(replies[0].error);
  assert.deepEqual(replies.slice(1).map(r => r.id), [7, 8]);
  assert.deepEqual(replies.slice(1).map(r => r.graph.nodes[0].id), ['A', 'C']);
});
