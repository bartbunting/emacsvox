// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later

// Drive the production stdio adapter and WebSocket from a fresh graphical Emacs.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const assert = require('node:assert/strict');
const { once } = require('node:events');
const { spawn } = require('node:child_process');
const { WebSocket } = require('ws');
const { createRelay } = require('../relay.cjs');

async function main() {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'iphone-speech-'));
  const relay = createRelay('127.0.0.1', '127.0.0.1');
  const socket = path.join(temp, 'speech.sock');
  let ws;
  try {
    relay.backend.listen(socket);
    await once(relay.backend, 'listening');
    relay.httpServer.listen(0, '127.0.0.1');
    await once(relay.httpServer, 'listening');
    ws = new WebSocket('ws://127.0.0.1:' + relay.httpServer.address().port + '/speech');
    await once(ws, 'message');
    const records = [];
    ws.on('message', bytes => records.push(JSON.parse(bytes)));
    const ping = setInterval(() => ws.send('ping'), 3000);
    try {
      const child = spawn('timeout', ['50', 'xvfb-run', '-a', './test-session', '-l',
        path.join(__dirname, 'navigation.el')], {
        cwd: path.join(__dirname, '..'), stdio: 'inherit',
        env: {...process.env, GDK_BACKEND:'x11', EMACSVOX_PHONE_SOCKET:socket},
      });
      const [code] = await once(child, 'exit');
      assert.equal(code, 0, 'Isolated Emacs navigation failed');
    } finally { clearInterval(ping); }

    // Automatic completion can arrive between key presses on the shared stream.
    assert.ok(records.some(r => /Starting row.*Cobalt lighthouse.*Amber orchard.*Last row/.test(r.text)),
      'Missing automatic reply');
    let last = -1;
    for (const target of ['Cobalt lighthouse', 'Amber orchard', 'Z', 'Notification probe']) {
      const index = records.findIndex((r, i) => i > last && r.text?.trim() === target);
      assert.ok(index > last, 'Missing ' + target);
      if (target !== 'Notification probe') {
        assert.ok(records.slice(last + 1, index).some(r => r.type === 'stop'), 'Missing stop before ' + target);
      }
      if (target === 'Z') assert.equal(records[index].type, 'letter');
      last = index;
    }
    const permission = records.findIndex((r, i) => i > last && /permission request/i.test(r.text));
    assert.ok(permission > last, 'Missing permission announcement');
    assert.ok(records.slice(permission + 1).some(r => r.type === 'stop'));
    const compose = records.findIndex((r, i) => i > permission && r.text?.trim() === 'Compose prompt');
    assert.ok(compose > permission, 'Missing interactive compose announcement');
    assert.deepEqual(records[compose - 1], {type: 'cue', name: 'open-object'},
      'The configured queued sound must precede the compose announcement');
    console.log('Passed two C-n moves, reply, permission, letter, notification, stop and the Agent Shell compose cue.');
  } finally {
    ws?.terminate();
    relay.backend.close();
    relay.httpServer.close();
    fs.rmSync(temp, {recursive:true, force:true});
  }
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
