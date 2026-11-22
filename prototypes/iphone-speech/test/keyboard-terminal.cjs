// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later

// Connect through the phone wire to a disposable Emacs terminal and its backend.
const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const { once } = require('node:events');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { setTimeout: delay } = require('node:timers/promises');
const { WebSocket } = require('ws');
const { createRelay } = require('../relay.cjs');

async function until(label, matches, timeout = 8000) {
  const end = Date.now() + timeout;
  while (Date.now() < end) {
    if (matches()) return;
    await delay(35);
  }
  throw Error('Timed out waiting for ' + label);
}

async function main() {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'emacskeys-'));
  const app = path.resolve(__dirname, '..');
  const socket = path.join(temp, 'speech.sock');
  const terminalSocket = path.join(temp, 'tmux.sock');
  const marker = path.join(temp, 'ready');
  const file = path.join(temp, 'keyboard.txt');
  const relay = createRelay('127.0.0.1', '127.0.0.1', {terminalSocket});
  const tmux = (...args) => execFileSync('tmux', ['-S', terminalSocket, ...args], {
    env: {...process.env, LC_ALL: 'C.UTF-8', XDG_RUNTIME_DIR: temp,
      EMACSVOX_PHONE_SOCKET: socket, EMACSVOX_KEYBOARD_READY: marker},
    stdio: 'ignore', timeout: 5000,
  });
  let ws, heartbeat, screen;
  let packets = [];
  async function connect() {
    packets = [];
    screen = '';
    ws = new WebSocket('ws://127.0.0.1:' + relay.httpServer.address().port + '/speech');
    ws.on('message', bytes => {
      const packet = JSON.parse(bytes);
      packets.push(packet);
      if (packet.type === 'screen') screen = packet.text;
    });
    await until('keyboard handshake', () => packets.some(p => p.type === 'ready' && p.keyboard));
  }
  const keys = text => ws.send('key ' + text);
  const screenHas = text => screen.includes(text);
  try {
    relay.backend.listen(socket);
    await once(relay.backend, 'listening');
    relay.httpServer.listen(0, '127.0.0.1');
    await once(relay.httpServer, 'listening');
    tmux('-f', '/dev/null', 'new-session', '-d', '-s', 'phone', '-x', '100', '-y', '32',
      path.join(app, 'test-session'), '-nw', '-l', path.join(__dirname, 'keyboard-session.el'));
    await until('test Emacs', () => fs.existsSync(marker), 45000);
    await connect();
    heartbeat = setInterval(() => { if (ws.readyState === WebSocket.OPEN) ws.send('ping'); }, 3000);
    await until('rendered response', () => screenHas('Phone keyboard sample'));
    for (const row of ['Cobalt lighthouse', 'Amber orchard']) {
      packets = [];
      keys('\x0e');
      await until(row + ' navigation speech', () => packets.some(p => p.type === 'speak' && p.text.trim().startsWith(row)));
      const cutoff = packets.findIndex(p => p.type === 'stop');
      assert.ok(cutoff >= 0 && cutoff < packets.findIndex(p => p.text?.trim().startsWith(row)));
    }
    keys('\x18\x06');
    await until('Find file prompt', () => screenHas('Find file'));
    keys(file + '\r');
    await until('file buffer', () => /F1\s+keyboard\.txt/.test(screen));
    const sentence = 'Café lantern 雪';
    keys(sentence);
    keys('\x18\x13');
    await until('saved UTF-8 file', () => fs.existsSync(file) && fs.readFileSync(file, 'utf8').trimEnd() === sentence);
    keys('\x1bx');
    await until('extended command prompt', () => screenHas('M-x'));
    keys('\x07');
    keys('\x18bPhone keyboard sample\r');
    await until('response after switch-buffer', () => screenHas('Cobalt lighthouse'));
    const closed = once(ws, 'close');
    ws.close();
    await closed;
    await connect();
    await until('terminal after reconnect', () => screenHas('Phone keyboard sample'));
    assert.ok(!packets.some(p => p.type === 'speak'));
    keys('\x10');
    await until('fresh speech after reconnect', () => packets.some(p => p.type === 'speak' && p.text.trim().startsWith('Cobalt lighthouse')));
    console.log('Passed terminal navigation and cutoff, UTF-8 file save, Escape x, cancel, buffer switch and reconnect.');
  } catch (error) {
    console.error('Packet kinds during the failed step:', packets.map(p => p.type).slice(-20).join(' '));
    throw error;
  } finally {
    clearInterval(heartbeat);
    ws?.terminate();
    try { tmux('kill-server'); } catch {}
    relay.httpServer.close();
    relay.backend.close();
    fs.rmSync(temp, {recursive: true, force: true});
  }
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
