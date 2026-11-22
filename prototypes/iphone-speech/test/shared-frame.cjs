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
const {createRelay, LegacyInput} = require('../relay.cjs');
const net = require('node:net');
const routed = process.argv.includes('--routed');

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
  const relay = createRelay('127.0.0.1', '127.0.0.1', {terminalSocket: tmuxSocket, sharedDirectory: dir, routed});
  const desktop = [];
  const desktopSocket = path.join(dir, 'desktop.sock');
  const pcBackend = net.createServer(s => {
    const input = new LegacyInput(p => desktop.push(p));
    s.on('data', bytes => input.write(bytes));
  });
  let gui, ws, client, heartbeat, pendingRequest;
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
    if (routed) {
      pcBackend.listen(desktopSocket);
      await once(pcBackend, 'listening');
    }
    relay.backend.listen(socket);
    await once(relay.backend, 'listening');
    relay.httpServer.listen(0, '127.0.0.1');
    await once(relay.httpServer, 'listening');
    tmux('-f', '/dev/null', 'start-server', ';', 'set-option', '-s', 'exit-empty', 'off');
    gui = spawn('xvfb-run', ['-a', './test-session', '-T', 'Emacsvox isolated route check', '-l', path.join(__dirname, 'shared-session.el')], {
      cwd: path.join(__dirname, '..'), detached: true, stdio: 'ignore',
      env: {...process.env, GDK_BACKEND: 'x11', XDG_RUNTIME_DIR: dir, EMACSVOX_PHONE_SOCKET: socket, EMACSVOX_SHARED_DIR: dir,
        ...(routed && {EMACSVOX_PHONE_SOCKET: desktopSocket, EMACSVOX_TRIAL_ROUTED: '1',
          EMACSVOX_TRIAL_DESKTOP_PROGRAM: path.resolve(__dirname, '../phone-backend')})},
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
    if (routed) {
      const phone = "(seq-find (lambda (f) (frame-parameter f 'emacsvox-phone-id)) (frame-list))";
      const position = (frame, row) => observe(`(set-window-point (frame-selected-window ${frame})
        (with-current-buffer iphone-shared-buffer (save-excursion (goto-char (point-min))
          (search-forward "${row}") (line-beginning-position))))`);
      // A server eval can inherit DISPLAY from the observing emacsclient.
      // Read the GUI child's startup values and match its exact test window.
      const xenv = {...process.env};
      for (const entry of fs.readFileSync('/proc/' + pid + '/environ', 'utf8').split('\0')) {
        const match = /^(DISPLAY|XAUTHORITY)=(.+)$/.exec(entry);
        if (match) xenv[match[1]] = match[2];
      }
      assert.match(xenv.DISPLAY, /^:\d+$/);
      assert.ok(Number(xenv.DISPLAY.slice(1)) >= 99 && xenv.XAUTHORITY.includes('/xvfb-run.'));
      const windows = (await run('xwininfo', ['-root', '-tree'], {env: xenv})).stdout;
      const windowId = windows.match(/(0x[\da-f]+) "Emacsvox isolated route check"/i)?.[1];
      assert.ok(windowId);
      assert.equal(Number(windowId), Number(JSON.parse(await observe(`(frame-parameter ${pc} 'outer-window-id)`))));
      const pressPC = (...keys) => run('python3', [path.join(__dirname, 'xvfb-key.py'), windowId, ...keys], {env: xenv});
      const spoke = (packets, row) => packets.some(p => p.type === 'speak' && p.text.trim() === row);
      await observe("(global-set-key (kbd \"<f8>\") #'tts-stop)");
      await position(pc, 'Starting row');
      await position(phone, 'Cobalt lighthouse');
      desktop.length = records.length = 0;
      ws.send('key \x0e');
      await until('phone C-n on the phone speaker', () => spoke(records, 'Amber orchard'));
      assert.ok(!spoke(desktop, 'Amber orchard'));
      await position(pc, 'Starting row');
      await pressPC('Control_L', 'n');
      await until('PC C-n on the desktop speaker', () => spoke(desktop, 'Cobalt lighthouse'));
      assert.ok(!spoke(records, 'Cobalt lighthouse'));
      // The phone is subscribed. A timer delivers an Agent Shell update
      // while the PC shows another buffer.
      await observe(`(with-selected-frame ${pc}
        (switch-to-buffer "*scratch*")
        (with-current-buffer iphone-shared-buffer
          (let ((emacsvox-agent-shell-speech-delay 0.05))
            (emacsvox-agent-shell--record-out-of-turn-snapshot
             '("out-of-turn-5-agent_message_chunk" . "Delayed copper lantern")))))`);
      await until('deferred update reaches subscribed phone', () => records.some(p => p.text?.includes('Delayed copper lantern')));
      assert.ok(!desktop.some(p => p.text?.includes('Delayed copper lantern')));
      await observe(`(with-selected-frame ${pc} (switch-to-buffer iphone-shared-buffer))`);
      await delay(250);
      desktop.length = records.length = 0;
      await pressPC('F8');
      await until('PC Stop', () => desktop.some(p => p.type === 'stop'));
      assert.ok(!records.some(p => p.type === 'stop'));
      desktop.length = records.length = 0;
      ws.send('key \x1b[19~');
      await until('phone Stop of both lanes', () => records.some(p => p.type === 'stop' && p.scope === 'all'));
      assert.ok(!desktop.some(p => p.type === 'stop'));
      records.length = 0;
      ws.send('key \x1bxtts-stop\r');
      await until('M-x tts-stop stops both phone lanes', () => records.some(p => p.type === 'stop' && p.scope === 'all'));
      await observe(`(global-set-key (kbd "<f7>") (lambda () (interactive)
        (tts-set-rate 135) (tts-letter "Z") (tts-tone 660 80 t)))`);
      ws.send('key \x1b[18~');
      await until('character and buffer-local phone rate', () => records.some(p => p.type === 'letter' && p.text === 'Z' && p.rate === 1.35));
      await until('queued tone from Emacs', () => records.some(p => p.type === 'tone' && p.hz === 660 && p.ms === 80));
      ws.send('reset 7');
      await until('Emacs Stop barrier', () => records.some(p => p.type === 'ready' && p.id === 7));
      assert.ok(!desktop.some(p => p.type === 'stop'));
      await observe(`(with-current-buffer iphone-shared-buffer
        (let ((tool '((:title . "Inspect test") (:permission-request-id . 17))))
          (map-put! agent-shell--state :tool-calls (list (cons "one" tool)))
          (agent-shell--emit-event :event 'permission-request
            :data (list '(:request-id . 17) '(:tool-call-id . "one") (cons :tool-call tool)))))`);
      await until('urgent permission on subscribed phone', () => records.some(p => p.type === 'permission'));
      pendingRequest = records.find(p => p.type === 'permission').id;
      assert.ok(pendingRequest);
      assert.ok(!desktop.some(p => /Inspect test/.test(p.text)));
    }
    await disconnect();
    assert.equal(await observe('(emacs-pid)'), pid);
    assert.ok(await pcSeesDraft('Started on PC first and phone'));
    const after = await connect();
    await until('same draft on reconnect', () => after.some(p => p.type === 'screen' && p.text.includes('Started on PC first and phone')));
    if (routed) {
      await until('pending request restored from Agent Shell state', () => after.some(p => p.type === 'permission' && p.id === pendingRequest));
      assert.equal(after.filter(p => p.type === 'permission' && p.id === pendingRequest).length, 1);
      await observe(`(progn
        (defvar iphone-second-test-buffer)
        (setq iphone-second-test-buffer (save-window-excursion (iphone-test-render-response)))
        (with-current-buffer iphone-second-test-buffer
          (rename-buffer "Second permission sample")
          (map-put! agent-shell--state :tool-calls
            '(("second" . ((:title . "Review copper") (:permission-request-id . 17)))))))`);
      async function switchPhoneBuffer(name) {
        const start = after.length;
        ws.send('key \x18b');
        await until('buffer prompt in the phone terminal', () =>
          after.slice(start).some(p => p.type === 'screen' && /switch to buffer/i.test(p.text)));
        ws.send('key ' + name + '\r');
      }
      await switchPhoneBuffer('Second permission sample');
      await until('switch restores the second conversation request', () =>
        after.some(p => p.type === 'permission' && p.id !== pendingRequest && p.text.includes('Review copper')))
        .catch(async error => {
          const state = await observe(`(let ((f (seq-find (lambda (f) (frame-parameter f 'emacsvox-phone-id)) (frame-list))))
            (with-selected-frame f (list (buffer-name (window-buffer)) last-command (minibuffer-depth)
              (buffer-name (frame-parameter f 'emacsvox-conversation)))))`);
          throw new Error(error.message + ', test frame state ' + state);
        });
      assert.ok(after.some(p => p.type === 'resolved' && p.id === pendingRequest));
      after.length = 0;
      await switchPhoneBuffer('Shared Codex sample');
      await until('return to first pending request', () => after.some(p => p.type === 'permission' && p.id === pendingRequest));
      await observe(`(with-current-buffer iphone-shared-buffer
        (map-put! agent-shell--state :tool-calls nil)
        (agent-shell--emit-event :event 'permission-response :data '((:request-id . 17) (:cancelled . t))))`);
      await until('permission resolution after returning', () => after.some(p => p.type === 'resolved' && p.id === pendingRequest));
    }
    const replaced = once(ws, 'close');
    const replacement = await connect(true);
    await replaced;
    await until('replacement frame', () => replacement.some(p => p.type === 'screen' && p.text.includes('Started on PC first and phone')));
    await until('previous frame removal', async () => (await observe('(length (frame-list))')) === '2');
    if (routed) {
      assert.ok(!replacement.some(p => p.type === 'permission'));
      console.log('Passed separate PC and phone navigation, explicit Stop, reset acknowledgement and permission recovery.');
    }
    await disconnect();
    if (routed && process.env.IPHONE_TEST_SSHD) {
      // Exercise the same opt-in attach and release used with an existing server.
      await observe("(remove-hook 'server-after-make-frame-hook #'iphone-shared-show-draft)");
      const pairDir = fs.mkdtempSync(path.join(dir, 'pair-'));
      const existing = action => run(path.resolve(__dirname, '../existing-session'),
        [action, client, path.join(dir, 'shared'), pairDir, 'Shared Codex sample']);
      await existing('attach');
      const sshRelay = createRelay('127.0.0.1', '127.0.0.1', {sharedDirectory: pairDir, routed: true, sshOnly: true});
      sshRelay.httpServer.listen(0, '127.0.0.1');
      await once(sshRelay.httpServer, 'listening');
      const probe = path.resolve(__dirname, '../ssh/.build/debug/SessionProbe');
      const seed = path.join(dir, 'seed'), pub = path.join(dir, 'test.pub');
      fs.writeFileSync(seed, require('node:crypto').randomBytes(32), {mode: 0o600});
      fs.writeFileSync(pub, execFileSync(probe, ['public-key', seed]));
      const peer = spawn('python3', [path.join(__dirname, 'ssh-terminal.py'), '--peer-only', pub,
        '--sshd', process.env.IPHONE_TEST_SSHD], {stdio: ['pipe', 'pipe', 'inherit']});
      let connection;
      try {
        const {port, pin} = JSON.parse((await once(peer.stdout, 'data'))[0]);
        async function attachSSH() {
          const packets = [];
          ws = new WebSocket('ws://127.0.0.1:' + sshRelay.httpServer.address().port + '/speech/ssh');
          ws.on('message', data => packets.push(JSON.parse(data)));
          await until('SSH pairing offer', () => packets.some(p => p.type === 'ssh'));
          const offer = packets.find(p => p.type === 'ssh');
          connection = spawn(probe, ['connect', seed, String(port), os.userInfo().username, pin,
            offer.server, offer.client, offer.frame], {stdio: ['pipe', 'pipe', 'inherit']});
          await until('SSH frame attached to its phone speech connection', () => packets.some(p => p.type === 'ready'), 25000);
          return packets;
        }
        async function closeSSH() {
          await disconnect();
          const exit = once(connection, 'exit');
          connection.stdin.end('wait\n');
          await exit;
          assert.equal(connection.exitCode, 0, 'SSH command ended after the speech peer left');
        }
        function sshKeys(bytes) { connection.stdin.write('input ' + Buffer.from(bytes).toString('base64') + '\n'); }
        const packets = await attachSSH();
        assert.ok(!packets.some(p => p.keyboard || p.type === 'screen'));
        await observe(`(set-window-point (frame-selected-window
          (seq-find (lambda (f) (frame-parameter f 'emacsvox-native-ssh)) (frame-list)))
          (with-current-buffer iphone-shared-buffer (save-excursion (goto-char (point-min))
            (search-forward "Starting row") (line-beginning-position))))`);
        desktop.length = 0;
        connection.stdin.write('input Dg==\n');
        await until('SSH C-n on the paired phone', () => packets.some(p => p.type === 'speak' && p.text.trim() === 'Cobalt lighthouse'));
        assert.ok(!desktop.some(p => p.text?.trim() === 'Cobalt lighthouse'));
        await observe('(global-set-key (kbd "<f6>") (lambda () (interactive) (switch-to-buffer (get-buffer-create "Phone resume draft"))))');
        sshKeys('\x1b[17~');
        const phoneWindow = "(frame-selected-window (seq-find (lambda (f) (frame-parameter f 'emacsvox-native-ssh)) (frame-list)))";
        await until('SSH edit buffer', async () => (await observe('(buffer-name (window-buffer ' + phoneWindow + '))')) === '"Phone resume draft"');
        packets.length = 0;
        await observe(`(with-current-buffer iphone-shared-buffer
          (let ((tool '((:title . "Inspect typing sample") (:permission-request-id . 23))))
            (map-put! agent-shell--state :tool-calls (list (cons "typing" tool)))
            (agent-shell--emit-event :event 'permission-request
              :data (list '(:request-id . 23) '(:tool-call-id . "typing") (cons :tool-call tool)))))`);
        await until('permission reaches the subscribed frame', () => packets.some(p => p.type === 'permission'));
        sshKeys('j');
        await until('character echo during permission', () => packets.some(p => p.type === 'letter' && p.text === 'j'));
        assert.ok(!packets.some(p => p.type === 'stop' && p.scope === 'all'));
        await closeSSH();
        await observe('(with-current-buffer "Phone resume draft" (save-excursion (goto-char (point-max)) (insert " other edits")))');
        const resumed = await attachSSH();
        await until('pending permission on resuming the edit buffer', () => resumed.some(p => p.type === 'permission'));
        assert.equal(resumed.filter(p => p.type === 'permission').length, 1);
        assert.equal(await observe('(buffer-name (window-buffer ' + phoneWindow + '))'), '"Phone resume draft"');
        assert.equal(await observe('(window-point ' + phoneWindow + ')'), '2');
        sshKeys('k');
        await until('fresh SSH input at the restored point', async () =>
          (await observe('(with-current-buffer "Phone resume draft" (buffer-string))')) === '"jk other edits"');
        await closeSSH();
        console.log('Passed native SSH navigation, protected typing echo and reconnect to the same buffer and point.');
      } finally {
        if (connection?.exitCode === null) connection.kill();
        peer.stdin.end();
        sshRelay.httpServer.close();
        await existing('release');
      }
      assert.equal(await observe('(emacs-pid)'), pid);
      assert.ok(await pcSeesDraft('Started on PC first and phone'));
      assert.equal(await observe("(advice-member-p #'iphone-frame-speech--stop 'tts-stop)"), 'nil');
      console.log('Released the existing server with the original PC draft and desktop speech intact.');
    }
    console.log('Passed editing one Agent Shell draft from PC and phone, closing only the phone frame, and reopening the same draft.');
  } finally {
    clearInterval(heartbeat);
    ws?.terminate();
    try { tmux('kill-server'); } catch {}
    if (gui && gui.exitCode === null) {
      const closed = once(gui, 'exit');
      // Xvfb-run's shell can exit before Emacs has handled its own signal.
      // These processes belong exclusively to the disposable Xvfb group.
      process.kill(-gui.pid, 'SIGKILL');
      await closed;
    }
    relay.httpServer.close();
    relay.backend.close();
    if (routed) pcBackend.close();
    fs.rmSync(dir, {recursive: true, force: true});
  }
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
