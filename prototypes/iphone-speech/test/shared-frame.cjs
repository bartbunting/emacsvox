// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later

const assert = require('node:assert/strict');
const {execFile, execFileSync, spawn} = require('node:child_process');
const {once} = require('node:events');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {setTimeout: delay} = require('node:timers/promises');
const run = require('node:util').promisify(execFile);
const {WebSocket} = require('ws');
const {createRelay} = require('../relay.cjs');

async function until(label, predicate, ms = 8000) {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    if (await predicate()) return;
    await delay(50);
  }
  throw new Error('Timed out waiting for ' + label);
}

async function main() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'shared-emacs-'));
  const socket = path.join(dir, 'speech.sock');
  const tmuxSocket = path.join(dir, 'tmux.sock');
  const tmux = (...args) => execFileSync('tmux', ['-S', tmuxSocket, ...args], {timeout: 3000});
  const relay = createRelay('127.0.0.1', '127.0.0.1', {terminalSocket: tmuxSocket, sharedDirectory: dir});
  let gui, ws, client, heartbeat;
  const observe = async expr => (await run(client, ['-a', '/bin/false', '-s', path.join(dir, 'shared'), '-e', expr],
    {timeout: 15000})).stdout.trim();
  const pc = '(seq-find (lambda (f) (display-graphic-p f)) (frame-list))';
  const pcBuffer = `(window-buffer (frame-selected-window ${pc}))`;
  const pcSeesDraft = async text => (await observe(`(with-current-buffer ${pcBuffer}
    (and (eq (current-buffer) iphone-shared-buffer)
         (equal (agent-shell--input) "${text}")))`)) === 't';
  async function connect(stopDuringAttach = false) {
    const current = new WebSocket('ws://127.0.0.1:' + relay.httpServer.address().port + '/speech');
    ws = current;
    const records = [];
    current.on('message', bytes => records.push(JSON.parse(bytes)));
    if (stopDuringAttach) current.once('open', () => current.send('reset 1'));
    await until('keyboard handshake', () => records.some(p => p.type === 'ready' && p.keyboard && p.id === Number(stopDuringAttach)));
    return records;
  }
  async function disconnect() {
    const closed = once(ws, 'close');
    ws.close();
    await closed;
    await until('phone frame removal', async () => (await observe('(length (frame-list))')) === '1');
  }
  try {
    relay.backend.listen(socket);
    await once(relay.backend, 'listening');
    relay.httpServer.listen(0, '127.0.0.1');
    await once(relay.httpServer, 'listening');
    tmux('-f', '/dev/null', 'start-server', ';', 'set-option', '-s', 'exit-empty', 'off');
    gui = spawn('xvfb-run', ['-a', './test-session', '-l', path.join(__dirname, 'shared-session.el')], {
      cwd: path.join(__dirname, '..'), detached: true, stdio: 'ignore',
      env: {...process.env, GDK_BACKEND: 'x11', XDG_RUNTIME_DIR: dir, EMACSVOX_PHONE_SOCKET: socket, EMACSVOX_SHARED_DIR: dir},
    });
    const marker = path.join(dir, 'ready');
    await until('PC draft and server', () => fs.existsSync(marker), 45000);
    client = fs.readFileSync(marker, 'utf8');
    const pid = await observe('(emacs-pid)');
    assert.ok(await pcSeesDraft('Started on PC'));
    await observe(`(with-current-buffer ${pcBuffer} (goto-char (point-max)) (insert " first"))`);
    assert.ok(await pcSeesDraft('Started on PC first'));
    const records = await connect();
    heartbeat = setInterval(() => { if (ws.readyState === WebSocket.OPEN) ws.send('ping'); }, 3000);
    ws.send('key  and phone');
    await until('PC draft on phone', () => records.some(p => p.type === 'screen' && p.text.includes('Started on PC first')));
    assert.equal(await observe('(cl-count-if (lambda (f) (eq (window-buffer (frame-selected-window f)) iphone-shared-buffer)) (frame-list))'), '2');
    await until('phone edit in PC draft', () => pcSeesDraft('Started on PC first and phone'));
    await disconnect();
    assert.equal(await observe('(emacs-pid)'), pid);
    assert.ok(await pcSeesDraft('Started on PC first and phone'));
    const after = await connect();
    await until('same draft on reconnect', () => after.some(p => p.type === 'screen' && p.text.includes('Started on PC first and phone')));
    const replaced = once(ws, 'close');
    const replacement = await connect(true);
    await replaced;
    await until('replacement frame', () => replacement.some(p => p.type === 'screen' && p.text.includes('Started on PC first and phone')));
    await until('previous frame removal', async () => (await observe('(length (frame-list))')) === '2');
    await disconnect();
    console.log('Passed editing one Agent Shell draft from PC and phone, closing only the phone frame, and reopening the same draft.');
  } finally {
    clearInterval(heartbeat);
    ws?.terminate();
    try { tmux('kill-server'); } catch {}
    if (gui && gui.exitCode === null) {
      const closed = once(gui, 'exit');
      process.kill(-gui.pid, 'SIGTERM');
      await closed;
    }
    relay.httpServer.close();
    relay.backend.close();
    fs.rmSync(dir, {recursive: true, force: true});
  }
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
