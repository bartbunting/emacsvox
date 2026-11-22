// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later

const { execFile } = require('node:child_process');
const { promisify } = require('node:util');
const run = promisify(execFile);

// The launcher owns this tmux socket and starts Emacs directly in its only pane.
function attachTerminal(socketPath, send, failed) {
  const options = { timeout: 2000, maxBuffer: 128 * 1024 };
  const pane = 'phone:0.0';
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
    active = false;
    pending = Buffer.alloc(0);
    clearInterval(timer);
  }};
}
module.exports = { attachTerminal };
