// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later
const test = require('node:test');
const assert = require('node:assert/strict');
const {once} = require('node:events');
const fs = require('node:fs/promises');
const net = require('node:net');
const os = require('node:os');
const path = require('node:path');
const {WebSocket} = require('ws');
const {Records, recordLimit} = require('../wire.cjs');
const {createRelay} = require('../relay.cjs');
const {openWire} = require('../wire-receiver');

test('UTF-8 split at a code point, exactly 512 KiB with CRLF, bad records then recovery', () => {
  const result = [], input = new Records(line => result.push(line));
  const bytes = Buffer.from('q {ê🦜}\n');
  for (const byte of bytes) input.write(Buffer.of(byte));
  input.write(Buffer.alloc(recordLimit, 0x61));
  input.write(Buffer.from('\r\n'));
  input.write(Buffer.alloc(recordLimit + 1, 0x62));
  input.write(Buffer.from('\n'));
  input.write(Buffer.from([0xc0, 0xff, 10]));
  input.write(Buffer.from('d\n'));
  assert.deepEqual(result.map(s => s.length), ['q {ê🦜}'.length, recordLimit, 1]);
  assert.equal(result[0], 'q {ê🦜}');
  assert.equal(result[2], 'd');
});

test('SSH carrier returns replies to the issuing worker, waits for both stop barriers and retires old sockets', {timeout: 8000}, async t => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'wire-'));
  const traceDirectory = path.join(directory, 'traces');
  const relay = createRelay('127.0.0.1', '127.0.0.1', {sharedDirectory: directory, routed: true, sshOnly: true, traceDirectory});
  await fs.writeFile(path.join(directory, 'ready'), '/bin/true');
  relay.httpServer.listen(0, '127.0.0.1');
  await once(relay.httpServer, 'listening');
  const sockets = [];
  t.after(async () => {
    for (const s of sockets) if (s instanceof WebSocket) s.terminate(); else s.destroy();
    relay.httpServer.close();
    await fs.rm(directory, {recursive: true, force: true});
  });
  async function connect() {
    const ws = new WebSocket('ws://127.0.0.1:' + relay.httpServer.address().port + '/speech/ssh/omnivox');
    sockets.push(ws);
    const msgs = require('node:events').on(ws, 'message', {close: ['close']});
    const next = async () => (await msgs.next()).value[0].toString();
    const offer = JSON.parse(await next());
    const open = async suffix => {
      const s = net.connect(path.join(directory, offer.frame + suffix));
      sockets.push(s);
      await once(s, 'connect');
      return s;
    };
    const main = await open('.sock'), notify = await open('.n');
    main.write('iphone_event ' + JSON.stringify({type: 'attached', id: offer.frame}) + '\n');
    assert.equal(JSON.parse(await next()).type, 'discovering');
    main.write('iphone_event ' + JSON.stringify({type: 'routing-ready', id: offer.frame}) + '\n');
    assert.deepEqual(JSON.parse(await next()), {type: 'ready', id: 0, speechTrace: true});
    return {ws, main, notify, next};
  }
  const first = await connect();
  await assert.rejects(fs.stat(traceDirectory), {code: 'ENOENT'});
  const traceFile = path.join(traceDirectory, 'last-speech-trace.log');
  const snapshot = 'Café test\nNamed bookmarks 0';
  first.ws.send('speech-trace ' + snapshot);
  assert.deepEqual(JSON.parse(await first.next()), {type: 'trace-saved', ok: true});
  first.ws.send('speech-trace ' + 'x'.repeat(65537));
  assert.deepEqual(JSON.parse(await first.next()), {type: 'trace-saved', ok: false});
  assert.equal(await fs.readFile(traceFile, 'utf8'), snapshot);
  assert.equal((await fs.stat(traceFile)).mode & 0o777, 0o600);
  const reply = '__OMNIVOX_CONTROL__ ' + 'A'.repeat(12000);
  for (const [tag, s] of [['M', first.main], ['N', first.notify]]) {
    s.write('omnivox_control {same-id}\r\n');
    assert.equal(await first.next(), tag + ' omnivox_control {same-id}');
    const received = once(s, 'data');
    first.ws.send(tag + ' ' + reply);
    assert.equal((await received)[0].toString(), reply + '\n');
  }
  first.ws.send('reset 9');
  first.ws.send('ping');
  assert.equal(JSON.parse(await first.next()).type, 'pong');
  const marker = 'iphone_event {"type":"reset-done","id":9}\n';
  first.main.write(marker + 'q barrier\n');
  assert.equal(await first.next(), 'M q barrier');
  first.notify.write(marker);
  assert.deepEqual(JSON.parse(await first.next()), {type: 'ready', id: 9, speechTrace: true});
  first.main.write('q partial');
  const closed = once(first.main, 'close');
  const second = await connect();
  await closed;
  second.main.write('q fresh\nd\n');
  assert.equal(await second.next(), 'M q fresh');
  assert.equal(await second.next(), 'M d');
  const ended = once(second.ws, 'close');
  second.ws.send('N __OMNIVOX_CONTROL__ x\ns');
  await ended;
});

test('local Stop and session-owned native replies during reconnect', async () => {
  const listeners = new Set(), stopped = [], sent = [];
  const native = {open: async () => {}, close: async () => {}, record: async () => {},
    stop: async id => { stopped.push(id); }, addListener: (_, f) => { listeners.add(f); return {remove: () => listeners.delete(f)}; }};
  const first = openWire(native, x => sent.push(x), assert.fail);
  first.stop();
  const old = [...listeners][0], oldId = stopped[0];
  first.close();
  const second = openWire(native, x => sent.push(x), assert.fail);
  second.stop();
  old({connection: oldId, record: 'M stale'});
  for (const f of listeners) {
    f({connection: oldId, record: 'N stale'});
    f({connection: stopped[1], record: 'N fresh'});
  }
  assert.deepEqual(sent, ['N fresh']);
  second.close();
});
