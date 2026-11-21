// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later

// This is a projection of Mermaid's language model, not a Mermaid parser.
import { detectFlowchart, parseFlowchart } from '@mermaid-js/diagram-flowchart/language';
import { entityAt } from '@mermaid-js/core/text';

export const MAX_SOURCE_BYTES = 256 * 1024;

// Only presentation markup is simplified. Unknown markup stays readable as
// source; labels, URLs and callbacks are never executed or fetched.
export function spokenLabel(raw, labelType) {
  let text = String(raw ?? '')
    .replace(/<br\s*\/?\s*>/gi, '; ')
    .replace(/<\/?(?:b|strong|i|em|u|s|span|div|p|small|code|sup|sub)(?:\s[^<>]*)?>/gi, '');
  if (labelType === 'markdown') {
    text = text.replace(/\*\*([^*]+)\*\*|__([^_]+)__/g, '$1$2')
      .replace(/\*([^*]+)\*|_([^_]+)_/g, '$1$2');
  }
  let decoded = '';
  for (let i = 0; i < text.length;) {
    const entity = text[i] === '&' && entityAt(text, i);
    if (entity) { decoded += entity[0]; i += entity[1]; }
    else { decoded += text[i++]; }
  }
  return decoded.replace(/[\s\x00-\x1f\x7f]+/g, ' ').trim();
}

export function project(source) {
  if (typeof source !== 'string' || Buffer.byteLength(source) > MAX_SOURCE_BYTES) {
    throw new Error('Diagram must be text of at most 256 KiB.');
  }
  if (!detectFlowchart(source)) {
    throw new Error('This prototype supports Mermaid flowcharts only.');
  }
  const parsed = parseFlowchart(source, { maxNodes: 1000, maxEdges: 2000, maxDepth: 50 });
  // Mermaid ranges count UTF-16 units; Emacs positions count Unicode characters.
  const offsets = new Uint32Array(source.length + 1);
  let units = 0, characters = 0;
  for (const character of source) {
    offsets[units] = characters;
    if (character.length === 2) offsets[units + 1] = characters;
    units += character.length;
    offsets[units] = ++characters;
  }
  const range = value => value ? {
    start: offsets[value.start], end: offsets[value.end],
  } : null;
  const diagnostics = parsed.diagnostics.map(d => ({
    severity: d.severity, code: d.code, message: d.message, range: range(d.range),
  }));
  // A recovered partial model must never be presented as a complete diagram.
  if (diagnostics.some(d => d.severity === 'error')) return { diagnostics, graph: null };
  const ast = new Map();
  const visit = node => {
    ast.set(node.id, node);
    for (const child of node.children ?? []) visit(child);
  };
  visit(parsed.ast);
  const location = id => {
    const node = ast.get(id);
    return range(node?.nameRange ?? node?.range);
  };
  const model = parsed.model;
  const groups = model.subgraphs.map(g => ({
    id: g.id, label: spokenLabel(g.title, g.labelType) || g.id,
    kind: 'group', shape: 'group', members: g.nodes,
    range: location(g.ast),
  }));
  const nodes = model.vertices.map(n => ({
    id: n.id, label: spokenLabel(n.text, n.labelType) || n.id,
    kind: 'node', shape: n.type ?? 'node', range: location(n.ast),
  }));
  // A named subgraph is also a possible edge endpoint. Keep one identity.
  const groupIds = new Set(groups.map(g => g.id));
  const objects = [...nodes.filter(n => !groupIds.has(n.id)), ...groups];
  for (const n of objects) n.groups = groups.filter(g => g.members.includes(n.id)).map(g => g.id);
  const ids = new Set(objects.map(n => n.id));
  const edges = model.edges.filter(e => e.stroke !== 'invisible').map((e, index) => {
    if (!ids.has(e.start) || !ids.has(e.end)) {
      throw new Error('Mermaid returned an unresolved connection endpoint.');
    }
    return {
      // Parallel edges need independent identities, including generated IDs.
      id: `${index}:${e.id}`, from: e.start, to: e.end,
      label: spokenLabel(e.text, e.labelType), stroke: e.stroke,
      arrow: e.type,
      direction: e.type === 'arrow_point' ? 'forward'
        : e.type === 'double_arrow_point' ? 'both' : 'none',
      range: location(e.ast),
    };
  });
  return { diagnostics, graph: {
    title: spokenLabel(model.accTitle) || 'Flowchart',
    description: spokenLabel(model.accDescr), direction: model.direction,
    nodes: objects, edges,
    hiddenEdges: model.edges.length - edges.length,
  } };
}
