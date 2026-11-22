// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later

const { execFile } = require('node:child_process');
const fs = require('node:fs/promises');
const path = require('node:path');
const { promisify } = require('node:util');
const run = promisify(execFile);

// Each shared-frame connection owns the tmux session that runs its emacsclient.
async function openPhoneFrame(socketPath, directory, session) {
  const client = await fs.readFile(path.join(directory, 'ready'), 'utf8');
  const tmux = (...args) => run('tmux', ['-N', '-S', socketPath, ...args], {timeout: 8000});
  await tmux('new-session', '-d', '-s', session,
    '-x', '100', '-y', '32', 'env', 'LC_ALL=C.UTF-8', client,
    '--alternate-editor=/bin/false', '--tty', '--socket-name=' + path.join(directory, 'shared'),
    '--frame-parameters=((emacsvox-phone-id . "' + session + '"))');
  try {
    // A new PTY can accept keys before Emacs has installed its terminal mode.
    await tmux('wait-for', session);
  } catch (error) {
    await tmux('kill-session', '-t', '=' + session).catch(() => {});
    throw error;
  }
  return session;
}

function attachTerminal(socketPath, send, failed, session = 'phone') {
  const options = { timeout: 2000, maxBuffer: 128 * 1024 };
  const pane = session + ':0.0';
  const tmux = (...args) => run('tmux', ['-S', socketPath, ...args], options);
  let active = true, writing = false, reading = false, lastScreen;
  let pending = Buffer.alloc(0);

  async function readScreen() {
    if (!active || reading) return;
    reading = true;
    try {
      const { stdout } = await tmux('capture-pane', '-p', '-t', pane);
      if (active && lastScreen !== stdout) {
        lastScreen = stdout;
        send({type: 'screen', text: stdout.trimEnd()});
      }
    } catch { if (active) failed(); }
    finally { reading = false; }
  }

  async function write(text) {
    if (!active) return;
    pending = Buffer.concat([pending, Buffer.from(text)]);
    if (pending.length > 8192) return failed();
    if (writing) return;
    writing = true;
    try {
      while (active && pending.length) {
        const chunk = pending.subarray(0, 512);
        pending = pending.subarray(chunk.length);
        const hex = Array.from(chunk, byte => byte.toString(16).padStart(2, '0'));
        await tmux('send-keys', '-H', '-t', pane, ...hex);
      }
    } catch { if (active) failed(); }
    finally { writing = false; }
  }
  const timer = setInterval(readScreen, 350);
  void readScreen();
  return { write, close() {
    if (!active) return;
    active = false;
    pending = Buffer.alloc(0);
    clearInterval(timer);
    if (session !== 'phone') void tmux('kill-session', '-t', '=' + session).catch(() => {});
  }};
}
async function sshOffer(directory, session) {
  return {type: 'ssh', frame: session, server: path.join(directory, 'shared'),
    client: await fs.readFile(path.join(directory, 'ready'), 'utf8')};
}

async function frameControl(directory, session, action, serial) {
  // Both the frame ID and the control action come from the relay.
  const {client, server} = await sshOffer(directory, session);
  await run(client, ['--alternate-editor=/bin/false', '--socket-name=' + server, '--eval',
    `(iphone-frame-speech-control "${session}" '${action} ${serial})`], {timeout: 5000});
}
module.exports = { attachTerminal, openPhoneFrame, frameControl, sshOffer };
