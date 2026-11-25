// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later

const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { once } = require('node:events');
const { connect } = require('node:net');
const { WebSocket } = require('ws');
const { createRelay, LegacyInput } = require('../relay.cjs');

test('line framing, UTF-8, queue order, stop and plain capabilities', () => {
  const packets = [];
  const input = new LegacyInput(p => packets.push(p));
  const wire = Buffer.from('omnivox_control {unused}\r\nq {discard}\ns\nq {café}\nc {voice}\nq {{雪}}\nd\nl { }\ntts_say {now}\n');
  for (const byte of wire) input.write(Buffer.from([byte]));
  assert.deepEqual(packets, [
    {type:'stop'}, {type:'speak', text:'café {雪}'},
    {type:'stop', scope:'speech'}, {type:'letter', text:' '},
    {type:'stop', scope:'speech'}, {type:'speak', text:'now'},
  ]);
});

test('dispatch preserves the Accent recording position and immediate play leaves the batch alone', () => {
  const packets = [];
  const input = new LegacyInput(packet => packets.push(packet));
  const file = path.resolve(__dirname, '../../../sounds/packs/accent/open-object.ogg');
  const quoted = JSON.stringify(file).replace(/[$[]/g, '\\$&');
  const write = wire => input.write(Buffer.from(wire));
  const queued = {type: 'cue', name: 'open-object'};
  write('q first\nq part\na ' + quoted + '\nq last\n');
  assert.deepEqual(packets, []);
  write('p ' + quoted + '\nd\n');
  assert.deepEqual(packets, [
    {...queued, immediate: true}, {type: 'speak', text: 'first part'},
    queued, {type: 'speak', text: 'last'},
  ]);
  packets.length = 0;
  write('a {' + file + '}\ns\nd\na ' + quoted + '\n');
  input.invalidate();
  write('d\np "/another/pack/open-object.ogg"\na ' + file + '\nd\n');
  assert.deepEqual(packets, [{type: 'stop'}, queued]);
});

test('receiver change drops partial records and queued fragments', () => {
  const packets = [];
  const input = new LegacyInput(p => packets.push(p));
  input.write(Buffer.from('q {old}\nq {par'));
  input.invalidate();
  input.write(Buffer.from('tial}\nq {old tail}\nd\nq {fresh}\nd\n'));
  assert.deepEqual(packets, [{type:'speak', text:'fresh'}]);
});

test('visual-line recording has a spoken fallback and follows legacy cue ordering and Stop', () => {
  const packets = [];
  const input = new LegacyInput(p => packets.push(p));
  const file = JSON.stringify(path.resolve(__dirname, '../assets/visual-line.wav')).replace(/[$[]/g, '\\$&');
  const cue = {type:'speak', text:'Visual lines', cue:'visual-line'};
  input.write(Buffer.from('q before\na ' + file + '\nq after\np ' + file + '\nd\n'));
  assert.deepEqual(packets, [{...cue, immediate:true}, {type:'speak', text:'before'}, cue, {type:'speak', text:'after'}]);
  packets.length = 0;
  input.write(Buffer.from('a ' + file + '\ns\nd\np "/unrelated/visual-line.wav"\n'));
  assert.deepEqual(packets, [{type:'stop'}]);
});

test('physical socket reset, receiver replacement and producer EOF', async t => {
  const {backend, httpServer} = createRelay('127.0.0.1', '127.0.0.1');
  for (const server of [backend, httpServer]) {
    server.listen(0, '127.0.0.1');
    await once(server, 'listening');
    t.after(() => server.close());
  }
  const writer = connect(backend.address().port, '127.0.0.1');
  t.after(() => writer.destroy());
  await once(writer, 'connect');
  const url = 'ws://127.0.0.1:' + httpServer.address().port + '/speech';
  const packet = async ws => JSON.parse((await once(ws, 'message'))[0]);
  const open = async () => {
    const ws = new WebSocket(url);
    t.after(() => ws.terminate());
    assert.deepEqual(await packet(ws), {type:'ready', id:0});
    return ws;
  };
  const old = await open();
  writer.write('q {sample}\nd\nq {stale}\n');
  assert.equal((await packet(old)).text, 'sample');
  const fresh = await open();
  const send = (wire, ws = fresh) => {
    const next = packet(ws);
    writer.write(wire);
    return next;
  };
  assert.equal((await send('d\nq {fresh}\nd\n')).text, 'fresh');
  fresh.send('reset 1');
  assert.deepEqual(await packet(fresh), {type:'ready', id:1});
  writer.end();
  assert.equal((await packet(fresh)).type, 'stop');
});

test('other peers and browser origins cannot subscribe', async t => {
  for (const [peer, origin] of [['127.0.0.2', undefined], ['127.0.0.1', 'https://example.org']]) {
    const {httpServer} = createRelay('127.0.0.1', peer);
    httpServer.listen(0, '127.0.0.1');
    await once(httpServer, 'listening');
    t.after(() => httpServer.close());
    const ws = new WebSocket('ws://127.0.0.1:' + httpServer.address().port + '/speech', {origin});
    await once(ws, 'error');
    assert.notEqual(ws.readyState, WebSocket.OPEN);
  }
});
