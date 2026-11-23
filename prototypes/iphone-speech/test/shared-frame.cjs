// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later

const assert = require('node:assert/strict');
const {execFile, execFileSync, spawn} = require('node:child_process');
const {on, once} = require('node:events');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {setTimeout: delay} = require('node:timers/promises');
const run = require('node:util').promisify(execFile);
const {WebSocket} = require('ws');
const {createRelay, LegacyInput} = require('../relay.cjs');
const {keyboardField} = require('./keyboard-field.cjs');
const net = require('node:net');
const routed = process.argv.includes('--routed');
const timeTones = process.argv.includes('--time-tones');

async function measureToneReturn(socket, pressReturn) {
  const messages = on(socket, 'message', {signal: AbortSignal.timeout(8000), close: ['close']});
  let stops = 0;
  const started = performance.now();
  try {
    pressReturn();
    for await (const [data] of messages) {
      const packet = JSON.parse(data);
      if (packet.type === 'stop') stops++;
      if (packet.type === 'tone' && packet.hz === 660 && packet.ms === 480) {
        return {ms: Math.round((performance.now() - started) * 10) / 10, stops};
      }
    }
    throw new Error('Connection closed before the comparison tone.');
  } finally {
    await messages.return();
  }
}

async function until(label, predicate, ms = 8000) {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    if (await predicate()) return;
    await delay(50);
  }
  throw new Error('Timed out waiting for ' + label);
}

async function main() {
  if (timeTones && (!routed || !process.env.IPHONE_TEST_SSHD)) {
    throw new Error('For tone timings use --routed and set IPHONE_TEST_SSHD to the test sshd.');
  }
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
    gui = spawn('xvfb-run', ['-a', './test-session', '-T', 'Emacsvox isolated route check',
      '--eval', "(setq native-comp-async-report-warnings-errors 'silent)", '-l', path.join(__dirname, 'shared-session.el')], {
      cwd: path.join(__dirname, '..'), detached: true, stdio: 'ignore',
      // Direct audio from the test Emacs must stay silent on the development machine.
      env: {...process.env, AUDIODRIVER: 'alsa', AUDIODEV: 'null', PULSE_SERVER: 'unix:' + path.join(dir, 'no-audio'),
        GDK_BACKEND: 'x11',
        XDG_RUNTIME_DIR: dir, EMACSVOX_PHONE_SOCKET: socket, EMACSVOX_SHARED_DIR: dir,
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
    if (routed) {
      // Create both conversations before opening the terminal. Starting
      // Agent Shell can select a window and interrupt a terminal prefix key.
      await observe(`(with-selected-frame ${pc}
        (defvar iphone-second-test-buffer)
        (setq iphone-second-test-buffer (save-window-excursion (iphone-test-render-response)))
        (with-current-buffer iphone-second-test-buffer
          (rename-buffer "Second permission sample")
          (map-put! agent-shell--state :tool-calls
            '(("second" . ((:title . "Review copper") (:permission-request-id . 17)))))))`);
    }
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
      // Exercise Emacs's prefix-message callback while the terminal is
      // waiting for the second physical key. Redisplay timing varies on Xvfb.
      await observe(`(with-selected-frame ${phone}
        (switch-to-buffer (get-buffer-create "PhoneModeFixture"))
        (org-mode) (visual-line-mode 1) (insert "Row one\\nWarmup row\\nLast row\\n") (goto-char (point-min))
        (setq sox-play "/bin/true" iphone-test-chimes 0)
        (advice-add 'sox-gen-cmd :before (lambda (cmd)
          (when (string-prefix-p sox-chime-cmd cmd) (cl-incf iphone-test-chimes)))))`);
      ws.send('key \x0e');
      await until('phone reads its Org window', () => records.some(p => p.type === 'speak' && p.text.includes('Warmup row')));
      desktop.length = records.length = 0;
      ws.send('key \x05');
      await until('real phone prefix is pending', async () =>
        (await observe(`(with-selected-frame ${phone} (key-description (this-single-command-keys)))`)) === '"C-e"');
      await observe(`(with-selected-frame ${phone}
        (let ((echo (help--append-keystrokes-help (concat (key-description (this-single-command-keys)) "-"))))
          (let ((emacsvox-speak-messages nil)) (message "%s" echo))
          (set-minibuffer-message echo)))`);
      await until('phone speaks its prefix help', () => records.some(p => p.type === 'speak' && /C-e.*for help/.test(p.text)));
      assert.ok(!desktop.some(p => p.type === 'speak' && /C-e.*for help/.test(p.text)));
      ws.send('key m');
      await until('phone reads its mode line', () => records.some(p => p.type === 'speak' && /PhoneModeFixture/i.test(p.text)));
      assert.equal(records.filter(p => p.cue === 'visual-line' && p.immediate).length, 1);
      assert.equal(await observe('iphone-test-chimes'), '0');
      await observe(`(global-set-key (kbd "<f4>") (lambda () (interactive)
        (let ((visual-line-mode t) (global-visual-line-mode nil)) (emacsvox-speak-mode-line))))`);
      await pressPC('F4');
      await until('desktop mode line still requests its SoX chime', async () => (await observe('iphone-test-chimes')) === '1');
      assert.equal(records.filter(p => p.cue === 'visual-line').length, 1);
      await observe(`(with-selected-frame ${phone} (message "Fixture desktop reminder"))`);
      await until('unrelated message still goes to desktop', () => spoke(desktop, 'Fixture desktop reminder'));
      assert.ok(!records.some(p => p.type === 'speak' && /Fixture desktop reminder/.test(p.text)));
      assert.ok(!desktop.some(p => p.type === 'speak' && /C-e|PhoneModeFixture/i.test(p.text)));
      // The phonetic word is delivered by a real idle timer after the
      // movement command has returned. Both speakers are recording packets.
      await observe(`(with-selected-window (frame-selected-window ${phone})
        (goto-char (point-min)) (forward-line 1))`);
      desktop.length = records.length = 0;
      ws.send('key \x1b[C');
      await until('phone reads the letter a', () => records.some(p => p.type === 'letter' && p.text === 'a'));
      await until('idle phonetic word alpha', () => spoke(records, 'alpha') || spoke(desktop, 'alpha'));
      assert.ok(spoke(records, 'alpha') && !spoke(desktop, 'alpha'), 'phone Alpha went to the desktop');
      await position(pc, 'Cobalt lighthouse');
      await pressPC('Right');
      await until('PC reads the letter o', () => desktop.some(p => p.type === 'letter' && p.text === 'o'));
      await until('PC phonetic word oscar', () => spoke(desktop, 'oscar'));
      assert.ok(!spoke(records, 'oscar'));
      await observe(`(with-selected-frame ${phone} (switch-to-buffer iphone-shared-buffer))`);
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
      await observe("(global-set-key (kbd \"<f5>\") #'iphone-test--steer)");
      const speaks = (packets, words) => packets.filter(p => p.type === 'speak' && p.text.includes(words)).length;
      const deliverSteering = frame => observe(`(with-selected-frame ${frame}
        (with-current-buffer iphone-test--reply-buffer
          (funcall iphone-test--acp-reply '((outcome . "injected")))))`);
      for (const onPhone of [true, false]) {
        const source = onPhone ? phone : pc, other = onPhone ? pc : phone;
        const local = onPhone ? records : desktop, remote = onPhone ? desktop : records;
        assert.equal(await observe(`(with-selected-frame ${source} (iphone-test--prepare-question ${onPhone ? 81 : 82}))`), 't');
        await observe(`(with-selected-frame ${other} (switch-to-buffer iphone-test--reply-buffer))`);
        // Exercise a phone form opened before its next subscription update and
        // a desktop form answered while the phone subscribes to the same shell.
        await observe(`(with-selected-frame ${phone}
          (iphone-frame-speech-subscribe ${onPhone ? 'iphone-shared-buffer' : 'iphone-test--reply-buffer'}))`);
        const start = local.length, otherStart = remote.length;
        if (onPhone) ws.send('key \r'); else await pressPC('Return');
        await until('answer confirmed on the submitting frame', () => speaks(local.slice(start), 'Answers sent'));
        if (onPhone) ws.send('key \x1b[15~'); else await pressPC('F5');
        await until('steering transport received the request', async () => await observe('(functionp iphone-test--acp-reply)') === 't');
        await deliverSteering(other);
        await until('deferred steering reaches its originating frame', () => speaks(local.slice(start), 'Steering accepted'));
        assert.equal(speaks(local.slice(start), 'Answers sent'), 1);
        assert.equal(speaks(local.slice(start), 'Steering accepted'), 1);
        assert.equal(speaks(remote.slice(otherStart), 'Answers sent') + speaks(remote.slice(otherStart), 'Steering accepted'), 0);
        await observe('(setq iphone-test--acp-reply nil)');
      }
      ws.send('key \x1b[15~');
      await until('another phone steering request is in flight', async () => await observe('(functionp iphone-test--acp-reply)') === 't');
      await observe(`(progn (with-selected-frame ${pc} (switch-to-buffer iphone-shared-buffer))
        (with-selected-frame ${phone} (switch-to-buffer iphone-shared-buffer)
          (iphone-frame-speech-subscribe iphone-shared-buffer)))`);
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
      const beforeOldReply = desktop.length;
      await observe(`(with-selected-frame ${pc} (with-current-buffer iphone-test--reply-buffer
        (funcall iphone-test--acp-reply '((outcome . "injected")))))`);
      assert.ok(![...after, ...desktop.slice(beforeOldReply)].some(p => p.type === 'speak' && p.text.includes('Steering accepted')));
      async function switchPhoneBuffer(name) {
        const start = after.length;
        // A process-exit message can cover the prompt between tmux snapshots.
        // Type the complete command and verify the resulting terminal window.
        ws.send('key \x18b' + name + '\r');
        const selectedBuffer = `(when-let* ((f (seq-find (lambda (frame) (frame-parameter frame 'emacsvox-phone-id))
                                                         (frame-list))))
                                 (buffer-name (window-buffer (frame-selected-window f))))`;
        await until('buffer name in the phone mode line', () => after.slice(start).some(p =>
          p.type === 'screen' && p.text.includes(name) && !/switch to buffer/i.test(p.text)));
        await until('selected phone buffer ' + name, async () =>
          await observe(selectedBuffer) === JSON.stringify(name));
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
      const sshRelay = createRelay('127.0.0.1', '127.0.0.1', {sharedDirectory: pairDir, routed: true, sshOnly: true, traceDirectory: pairDir});
      sshRelay.httpServer.listen(0, '127.0.0.1');
      await once(sshRelay.httpServer, 'listening');
      const probe = path.resolve(__dirname, '../ssh/.build/debug/SessionProbe');
      const seed = path.join(dir, 'seed'), pub = path.join(dir, 'test.pub');
      fs.writeFileSync(seed, require('node:crypto').randomBytes(32), {mode: 0o600});
      fs.writeFileSync(pub, execFileSync(probe, ['public-key', seed]));
      const peer = spawn('python3', [path.join(__dirname, 'ssh-terminal.py'), '--peer-only', pub,
        '--sshd', process.env.IPHONE_TEST_SSHD], {stdio: ['pipe', 'pipe', 'inherit']});
      let connection, controlAudio;
      try {
        const {port, pin} = JSON.parse((await once(peer.stdout, 'data'))[0]);
        async function attachSSH(rawWorker) {
          const packets = [];
          ws = new WebSocket('ws://127.0.0.1:' + sshRelay.httpServer.address().port + '/speech/ssh' + (rawWorker ? '/omnivox' : ''));
          const current = ws, workers = {};
          controlAudio = (lane, line) => workers[lane].stdin.write(line + '\n');
          if (rawWorker) {
            for (const tag of ['M', 'N']) {
              const worker = spawn(rawWorker, [], {stdio: ['pipe', 'pipe', 'inherit']});
              workers[tag] = worker;
              require('node:readline').createInterface({input: worker.stdout}).on('line', line => {
                if (line.startsWith('test-audio ')) { packets.push({lane: tag, audio: line.slice(11)}); return; }
                const marker = /^__EMACSVOX_MARKER__ ([A-Za-z0-9+/=]+)$/.exec(line);
                const result = /^__OMNIVOX_CONTROL__ ([A-Za-z0-9+/=]+)$/.exec(line);
                if (result) {
                  const reply = JSON.parse(Buffer.from(result[1], 'base64'));
                  packets.push({lane: tag, response: reply.type, requestId: reply.request_id, generation: reply.registry_generation,
                    unresolved: reply.unresolved_logical_voice_ids?.length});
                }
                const receipt = /^__EMACSVOX_TRACKED__ (\d+) (completed|cancelled|failed)$/.exec(line);
                if (marker) packets.push({lane: tag, marker: JSON.parse(Buffer.from(marker[1], 'base64'))});
                if (receipt) packets.push({lane: tag, dispatch: Number(receipt[1]), status: receipt[2]});
                if (current.readyState === WebSocket.OPEN) current.send(tag + ' ' + line);
              });
            }
            current.once('close', () => Object.values(workers).forEach(worker => worker.stdin.end()));
          }
          ws.on('message', data => {
            const message = data.toString();
            if (rawWorker && /^[MN] /.test(message)) {
              workers[message[0]].stdin.write(message.slice(2) + '\n');
              const line = message.slice(2);
              const icon = /^[ap]\s/.test(line) && /(omnivox-icon:personal\/[a-f0-9]{64})/.exec(line);
              const tone = /^emacsvox_tone 1 (insert|overlay) ([\d.]+) (\d+)$/.exec(line);
              const encoded = /^omnivox_control\s+\{?([A-Za-z0-9+/=]+)\}?$/.exec(line);
              const control = encoded && JSON.parse(Buffer.from(encoded[1], 'base64').toString());
              const encodedTimeline = /^(?:emacsvox_timeline|emacsvox_letter)\s+\{?([A-Za-z0-9+/=]+)\}?$/.exec(line);
              const timeline = encodedTimeline && JSON.parse(Buffer.from(encodedTimeline[1], 'base64'));
              if (timeline?.protocol_version >= 4) {
                timeline.spanModes = timeline.spans.map(s => s.mode);
                timeline.spans = timeline.spans.map(s => s.span);
              }
              const volume = /^tts_set_(voice|tone|sound)_volume (\S+)$/.exec(line);
              packets.push({lane: message[0], command: line.split(' ')[0], icon: icon?.[1],
                timingSerial: /^q \{timing sample (\d+) \}$/.exec(line)?.[1],
                timeline, volume: volume && {kind: volume[1], value: Number(volume[2])},
                control: control?.type, voice: control?.selector?.voice_id, requestId: control?.request_id,
                previewChoice: control?.voice?.choices?.find(c => c.id === control.selection?.choice_id),
                roleVoices: control?.definitions && Object.fromEntries(control.definitions.map(row => {
                  const definition = row.definition ?? row;
                  return [definition.id, definition.choices?.[0]?.selector?.voice_id ?? definition.preferences?.[0]?.voice_id];
                })),
                fixtureRow: /^q\s/.test(line) && line.includes('Fixture') || timeline?.spans.some(span => span.text.includes('Fixture')),
                tone: tone && {mode: tone[1], hz: Number(tone[2]), ms: Number(tone[3])}});
            } else packets.push(JSON.parse(message));
          });
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
        const phoneWindow = "(frame-selected-window (seq-find (lambda (f) (frame-parameter f 'emacsvox-native-ssh)) (frame-list)))";
        const packets = await attachSSH();
        assert.ok(!packets.some(p => p.keyboard || p.type === 'screen'));
        const beforeKeys = await observe('(window-point ' + phoneWindow + ')');
        await observe('(with-selected-window ' + phoneWindow + ' (switch-to-buffer (get-buffer-create "Phone modifier sample")) ' +
          '(emacs-lisp-mode) (insert "(one two) (three four)") (goto-char 5))');
        const field = keyboardField(sshKeys);
        const controlMetaField = keyboardField(sshKeys, true);
        const hyper = keyboardField(sshKeys, false, true);
        const chords = [
          ['H-x', 'x', {code:'KeyX'}], ['C-H-f', 'f', {code:'KeyF', ctrlKey:true}],
          ['H-M-r', 'r', {code:'KeyR', altKey:true}], ['H-<left>', 'ArrowLeft', {}],
          ['H->', '>', {code:'Period', shiftKey:true}],
        ];
        await observe(`(with-selected-window ${phoneWindow} (use-local-map (copy-keymap (current-local-map)))
          (setq-local iphone-test-hyper-events nil)
          ${chords.map(([name]) => `(local-set-key (kbd "${name}") (lambda () (interactive) (push "${name}" iphone-test-hyper-events)))`).join(' ')})`);
        for (const [name, key, modifiers] of chords) {
          assert.ok(hyper.down(key, {metaKey:true, ...modifiers}));
          await until('SSH receives ' + name, async () => await observe(`(with-selected-window ${phoneWindow}
            (equal (car iphone-test-hyper-events) "${name}"))`) === 't');
        }
        const atPoint = async position => (await observe('(window-point ' + phoneWindow + ')')) === String(position);
        assert.ok(field.down('˘', {code:'Period', altKey:true, shiftKey:true}));
        await until('SSH Meta end of buffer', () => atPoint(23));
        assert.ok(field.down('¯', {code:'Comma', altKey:true, shiftKey:true}));
        await until('SSH Meta beginning of buffer', () => atPoint(1));
        assert.ok(controlMetaField.down('ƒ', {code:'KeyF', ctrlKey:true, altKey:true}));
        await until('SSH Control+Option forward-sexp', () => atPoint(10));
        assert.ok(field.down('Escape'));
        assert.ok(field.down('f', {ctrlKey:true}));
        await until('SSH Escape then Control+f', () => atPoint(23));
        assert.equal(await observe('(with-current-buffer "Phone modifier sample" (buffer-substring-no-properties (point-min) (point-max)))'),
          '"(one two) (three four)"');
        console.log('Passed Meta buffer boundaries and both Control+Meta inputs through the Swift SSH client to Emacs.');
        const draft = 'Started on PC first and phone';
        await observe(`(with-selected-window ${phoneWindow} (switch-to-buffer iphone-shared-buffer)
          (goto-char (point-max)) (emacsvox-agent-shell-edit-input))`);
        assert.ok(field.down('j', {code:'KeyJ'}));
        await until('one literal j in the draft', () => pcSeesDraft(draft + 'j'));
        assert.ok(field.down('Return', {code:'Enter', shiftKey:true}));
        assert.ok(field.down('J', {code:'KeyJ', shiftKey:true}));
        await until('Shift+Return inserts one newline in the unsent Agent Shell draft',
          () => pcSeesDraft(draft + 'j\nJ'));
        assert.ok(field.down('j', {code:'KeyJ', ctrlKey:true}));
        assert.ok(field.down('k', {code:'KeyK'}));
        await until('Control+j also inserts an unsent newline', () => pcSeesDraft(draft + 'j\nJ\nk'));
        await observe(`(with-selected-window ${phoneWindow}
          (goto-char (point-max)) (delete-region (- (point) 5) (point))
          (goto-char (point-min)) (emacsvox-agent-shell--input-sync)
          (setq-local iphone-test-response-keys nil)
          (add-hook 'pre-command-hook (lambda ()
            (when (memq this-command '(emacsvox-agent-shell-next-response emacsvox-agent-shell-previous-response))
              (push this-command iphone-test-response-keys))) nil t))`);
        const nav = packets.length;
        assert.ok(field.down('j', {code:'KeyJ'}));
        await until('spoken response navigation for j', () => packets.slice(nav).some(p => p.type === 'speak' && p.text.trim()));
        const back = packets.length;
        assert.ok(field.down('J', {code:'KeyJ', shiftKey:true}));
        await until('spoken response navigation for Shift+j', () => packets.slice(back).some(p => p.type === 'speak' && p.text.trim()));
        await until('j and Shift+j navigate Agent Shell responses', async () =>
          (await observe(`(with-current-buffer iphone-shared-buffer (equal iphone-test-response-keys
            '(emacsvox-agent-shell-previous-response emacsvox-agent-shell-next-response)))`)) === 't')
          .catch(async error => { throw new Error(error.message + ': ' + await observe(`(with-selected-window ${phoneWindow}
            (list (key-binding "j") (key-binding "J") (buffer-name) (point) iphone-test-response-keys))`)); });
        assert.ok(await pcSeesDraft(draft));
        assert.ok(!packets.slice(nav).some(p => p.type === 'letter' && /^[jJ]$/.test(p.text)));
        await observe(`(with-selected-window ${phoneWindow} (goto-char ${beforeKeys}) (emacsvox-agent-shell--input-sync))`);
        console.log('Passed printable input, Shift+Return in an unsent draft and j/J transcript navigation over native SSH.');
        const otherSounds = path.join(dir, 'second installation', 'sounds');
        const relativeCue = 'packs/accent/open-object.ogg';
        const otherCue = path.join(otherSounds, relativeCue);
        fs.mkdirSync(path.dirname(otherCue), {recursive: true});
        fs.copyFileSync(path.resolve(__dirname, '../../../sounds', relativeCue), otherCue);
        await observe(`(global-set-key (kbd "<f5>") (lambda () (interactive)
          (let ((emacsvox-sounds-dir ${JSON.stringify(otherSounds)}) (emacsvox-play-program "/bin/false"))
            (emacsvox-aural-call-with-submission (lambda ()
              (let ((file (expand-file-name "${relativeCue}" emacsvox-sounds-dir)))
                (emacsvox-sounds-play-concrete-cue file "open-object")
                (emacsvox-queue-resource file)
                (tts-tone 520 40 t)))))))`);
        const playCues = async () => {
          const start = packets.length;
          sshKeys('\x1b[15~');
          await until('cue submission reached the receiver', () =>
            packets.slice(start).some(p => p.type === 'tone' && p.hz === 520));
          return packets.slice(start).filter(p => p.type === 'cue');
        };
        assert.deepEqual(await playCues(), [
          {type:'cue', name:'open-object', immediate:true}, {type:'cue', name:'open-object'},
        ]);
        assert.equal(JSON.parse(await observe(`(omnivox-remote-resource ${JSON.stringify(otherCue)})`)), otherCue);
        fs.writeFileSync(otherCue, 'different recording');
        assert.deepEqual(await playCues(), []);
        console.log('Passed immediate and queued Accent from a second installation and skipped a different recording.');
        await observe(`(set-window-point (frame-selected-window
          (seq-find (lambda (f) (frame-parameter f 'emacsvox-native-ssh)) (frame-list)))
          (with-current-buffer iphone-shared-buffer (save-excursion (goto-char (point-min))
            (search-forward "Starting row") (line-beginning-position))))`);
        desktop.length = 0;
        connection.stdin.write('input Dg==\n');
        await until('SSH C-n on the paired phone', () => packets.some(p => p.type === 'speak' && p.text.trim() === 'Cobalt lighthouse'));
        assert.ok(!desktop.some(p => p.text?.trim() === 'Cobalt lighthouse'));
        // Move over the o to the b before the phonetic timer expires.
        sshKeys('\x1b[C\x1b[C');
        await until('newest SSH letter is described', () =>
          packets.some(p => p.type === 'speak' && p.text.trim() === 'bravo'));
        assert.ok(!packets.some(p => p.type === 'speak' && p.text.trim() === 'oscar'));
        assert.ok(!desktop.some(p => p.type === 'speak' && ['oscar', 'bravo'].includes(p.text.trim())));
        sshKeys('\x15\x1bxiphone-test-tone\r');
        await until('the Emacs tone matches the Diagnostics tone', () =>
          packets.some(p => p.type === 'tone' && p.hz === 660 && p.ms === 480));
        await until('read-only tone comparison has the Return key', async () => (await observe(
          `(with-selected-window ${phoneWindow} (and buffer-read-only (eq (key-binding (kbd "RET")) 'iphone-test-tone)))`)) === 't');
        if (timeTones) {
          const samples = {direct: [], minibuffer: []};
          for (let pair = 0; pair < 7; pair++) {
            for (const kind of (pair % 2 ? ['direct', 'minibuffer'] : ['minibuffer', 'direct'])) {
              if (kind === 'minibuffer') {
                sshKeys('\x1bxiphone-test-tone');
                await until('M-x is ready for Return', async () => (await observe(
                  `(with-selected-frame (window-frame ${phoneWindow})
                     (when-let* ((mini (active-minibuffer-window)))
                       (with-current-buffer (window-buffer mini)
                         (equal (minibuffer-contents-no-properties) "iphone-test-tone"))))`)) === 't');
              }
              await delay(120);
              samples[kind].push(await measureToneReturn(ws, () => sshKeys('\r')));
            }
          }
          console.log('Loopback SSH Return to tone packet (milliseconds and Stop counts):', JSON.stringify(samples));
        }
        const beforeRepeat = packets.length;
        sshKeys('\r');
        await until('Return repeats the comparison tone outside the minibuffer', () =>
          packets.slice(beforeRepeat).some(p => p.type === 'tone' && p.hz === 660 && p.ms === 480));
        assert.ok(!desktop.some(p => p.type === 'tone' && p.hz === 660 && p.ms === 480));
        sshKeys('q');
        await until('comparison returns to the conversation', async () =>
          (await observe(`(eq (window-buffer ${phoneWindow}) iphone-shared-buffer)`)) === 't');
        await observe('(global-set-key (kbd "<f6>") (lambda () (interactive) (switch-to-buffer (get-buffer-create "Phone resume draft"))))');
        sshKeys('\x1b[17~');
        await until('SSH edit buffer', async () => (await observe('(buffer-name (window-buffer ' + phoneWindow + '))')) === '"Phone resume draft"');
        packets.length = 0;
        await observe('(with-selected-window ' + phoneWindow + ' (iphone-test-permission) nil)');
        await until('practice permission reaches the subscribed frame', () =>
          packets.some(p => p.type === 'permission' && /lighthouse notes.*Allow once.*Reject/.test(p.text)));
        assert.ok(field.down('j', {code:'KeyJ'}));
        await until('character echo during permission', () => packets.some(p => p.type === 'letter' && p.text === 'j'));
        assert.ok(!packets.some(p => p.type === 'stop' && p.scope === 'all'));
        await closeSSH();
        assert.equal(packets.filter(p => p.type === 'letter' && p.text === 'j').length, 1);
        await observe('(with-current-buffer "Phone resume draft" (save-excursion (goto-char (point-max)) (insert " other edits")))');
        const resumed = await attachSSH();
        await until('pending permission on resuming the edit buffer', () => resumed.some(p => p.type === 'permission'));
        assert.equal(resumed.filter(p => p.type === 'permission').length, 1);
        assert.equal(await observe('(buffer-name (window-buffer ' + phoneWindow + '))'), '"Phone resume draft"');
        assert.equal(await observe('(window-point ' + phoneWindow + ')'), '2');
        sshKeys('k');
        await until('fresh SSH input at the restored point', async () =>
          (await observe('(with-current-buffer "Phone resume draft" (buffer-string))')) === '"jk other edits"');
        const originalRequest = resumed.find(p => p.type === 'permission').id;
        await observe(`(with-selected-window ${phoneWindow} (switch-to-buffer "PhoneModeFixture") (goto-char (point-min)))`);
        sshKeys('\x15\x1bxiphone-test-permission\r');
        await until('permission practice is armed', async () => (await observe('(frame-live-p iphone-test--armed-frame)')) === 't');
        sshKeys('\x0e');
        await until('first move starts a fresh practice request', () =>
          resumed.some(p => p.type === 'permission' && p.id !== originalRequest));
        const newRequest = resumed.find(p => p.type === 'permission' && p.id !== originalRequest).id;
        assert.ok(resumed.some(p => p.type === 'resolved' && p.id === originalRequest));
        const beforeMove = resumed.length;
        sshKeys('\x0e');
        await until('second move speaks its line', () =>
          resumed.slice(beforeMove).some(p => p.type === 'speak' && p.text.trim() === 'Last row'));
        assert.ok(!resumed.slice(beforeMove).some(p => p.type === 'stop' && p.scope === 'all'));
        sshKeys('\x1bxiphone-test-permission\r');
        await until('phone reviews the pending choices', async () => (await observe(
          '(with-selected-window ' + phoneWindow + ' (get-text-property (point) \'agent-shell-permission-button))')) === 't');
        sshKeys('y');
        await until('phone answers the practice request', () =>
          resumed.some(p => p.type === 'resolved' && p.id === newRequest));
        await observe(`(with-selected-window ${phoneWindow}
          (switch-to-buffer "PhoneModeFixture") (goto-char (point-min)) (forward-line 1))`);
        desktop.length = 0;
        const beforeDetach = resumed.length;
        sshKeys('\x1b[C');
        await until('a pending SSH letter before disconnect', () =>
          resumed.slice(beforeDetach).some(p => p.type === 'letter' && p.text === 'a'));
        assert.equal(await observe('(and emacsvox--delayed-phonetic-request t)'), 't');
        await closeSSH();
        const attached = await attachSSH();
        // Leave the new frame idle longer than the discarded request's delay.
        const phoneticDelay = Number(await observe('emacsvox-delayed-phonetic-delay'));
        await delay(phoneticDelay * 1000 + 100);
        assert.ok(![...desktop, ...attached].some(p => p.type === 'speak' && p.text.trim() === 'alpha'));
        sshKeys('\x1b[C');
        await until('fresh phonetic speech after reconnect', () =>
          attached.some(p => p.type === 'speak' && p.text.trim() === 'romeo'));
        await closeSSH();
        if (process.env.IPHONE_WIRE_WORKER) {
          await observe('(setq-default tts-main-tone-volume 50 tts-notification-tone-volume 90 tts-main-earcon-volume 45)');
          const rawPackets = await attachSSH(process.env.IPHONE_WIRE_WORKER);
          const phone = `(window-frame ${phoneWindow})`;
          const main = `(frame-parameter ${phone} 'emacsvox-phone-speaker)`;
          const notification = `(process-get ${main} 'iphone-notify)`;
          await until('both Omnivox workers discovered and registered', async () =>
            await observe(`(cl-every (lambda (p) (and (equal "ios" (plist-get (process-get p omnivox--control-inventory-property) :preferred_engine_id))
              (process-get p omnivox--control-registration-property))) (list ${main} ${notification}))`) === 't', 30000);
          const desktopSnapshot = '(list (process-name tts-speaker-process) omnivox-engine-inventory omnivox-available-voices omnivox-default-voice-id)';
          const desktopState = await observe(desktopSnapshot);
          const editorPosition = `(with-selected-window ${phoneWindow}
            (list (buffer-name) (point) (buffer-chars-modified-tick)))`;
          const beforeTiming = await observe(editorPosition);
          assert.ok(rawPackets.some(p => p.type === 'ready' && p.keyTiming === true));
          sshKeys('\x1b[57343;17u');
          await until('one diagnostic key returns its numbered speech on the phone', () => {
            const queued = rawPackets.findIndex(p => p.lane === 'M' && p.timingSerial === '17');
            return queued >= 0 && rawPackets.slice(queued + 1).some(p => p.lane === 'M' && p.command === 'd');
          });
          assert.equal(await observe(editorPosition), beforeTiming, 'the diagnostic key leaves the conversation untouched');
          console.log('The numbered timing key returned on the main phone worker and preserved the buffer and point.');
          const registrationTests = JSON.stringify(path.join(__dirname, 'voice-registration.el'));
          assert.equal(await observe(`(progn (load ${registrationTests} nil t t)
            (ert-stats-completed-unexpected (ert-run-tests-batch "^iphone-registration-")))`), '0');
          const hasVolume = (packets, lane, kind, value) => packets.some(p =>
            p.lane === lane && p.volume?.kind === kind && p.volume.value === value);
          assert.ok(hasVolume(rawPackets, 'M', 'tone', 0.5) && hasVolume(rawPackets, 'N', 'tone', 0.9));
          assert.ok(hasVolume(rawPackets, 'M', 'sound', 0.45));
          const muteFrom = rawPackets.length;
          await observe(`(let ((iphone-frame-speech--settings '(:tone 0.0)))
            (mapc #'iphone-voices--restore (list ${main} ${notification})))`);
          await until('explicit zero tone volume on both phone lanes', () =>
            ['M', 'N'].every(lane => hasVolume(rawPackets.slice(muteFrom), lane, 'tone', 0)));
          await observe(`(mapc #'iphone-voices--restore (list ${main} ${notification}))`);
          for (const ok of [true, false]) {
            const start = rawPackets.length;
            const words = ok ? 'Speech trace saved in WSL.' : 'WSL could not save the speech trace.';
            ws.send('speech-trace ' + (ok ? 'private synthetic test' : ''));
            const confirms = p => p.timeline?.spans.some(s => s.text.includes(words));
            await until('trace result acknowledged and spoken on the phone notification lane', () => {
              const fresh = rawPackets.slice(start);
              return fresh.some(p => p.type === 'trace-saved' && p.ok === ok) &&
                fresh.some(p => p.lane === 'N' && confirms(p));
            });
            assert.ok(!rawPackets.slice(start).some(p => p.lane === 'M' && confirms(p)));
            assert.ok(!desktop.some(p => p.text?.includes(words)));
          }
          assert.equal(fs.readFileSync(path.join(pairDir, 'last-speech-trace.log'), 'utf8'), 'private synthetic test');
          await observe(`(with-selected-window ${phoneWindow}
            (switch-to-buffer (iphone-test-render-response "Timing start\nTestCase\nFresh line\nLime Plum Pear Fig Café"))
            (setq-local tts-caps t tts-split-caps nil emacsvox-capitalization-presentation 'tone)
            (goto-char (point-min)) (search-forward "Timing start") (beginning-of-line))`);
          const firstNavigation = rawPackets.length;
          sshKeys('\x0e');
          const word = () => rawPackets.slice(firstNavigation).find(p =>
            p.lane === 'M' && p.timeline?.spans.some(span => span.text.includes('TestCase')))?.timeline;
          await until('ordinary Control+n delivers an intact TestCase timeline to the iPhone worker', word);
          assert.equal(word().protocol_version, 7, 'navigation uses the negotiated desktop tone format');
          const inner = word().actions.find(action => action.type === 'tone' && action.position.utf8_offset === 4);
          assert.equal(inner?.mode, 'insert');
          await until('the marked navigation dispatch completes after its semantic cue', () =>
            rawPackets.some(p => p.lane === 'M' && p.dispatch === word().dispatch_id && p.status === 'completed') &&
            rawPackets.some(p => p.lane === 'M' && p.marker?.dispatch_id === word().dispatch_id &&
              p.marker.type === 'semantic_event_reached')).catch(error => {
            const id = word().dispatch_id;
            const receipts = rawPackets.filter(p => p.lane === 'M' && p.dispatch === id).map(p => p.status);
            const registrations = rawPackets.filter(p => p.lane === 'M' && p.response).map(
              p => [p.response, p.generation, p.unresolved]);
            throw new Error(error.message + ', dispatch ' + id + ' registry ' + word().registry_generation +
              ' receipts ' + JSON.stringify(receipts) + ' setup ' + JSON.stringify(registrations.slice(-15)));
          });
          const played = rawPackets.filter(p => p.marker?.dispatch_id === word().dispatch_id).map(p => p.marker);
          assert.ok(played.some(m => m.type === 'utterance_started' && m.text.includes('TestCase')));
          assert.ok(played.some(m => m.type === 'timeline_action_resolved' && m.action_id === inner.id && m.resolution === 'exact'));
          await observe(`(with-selected-window ${phoneWindow} (search-forward "Fresh line") (beginning-of-line))`);
          const fiveStart = rawPackets.length;
          sshKeys('\x0e');
          const five = () => rawPackets.slice(fiveStart).find(p => p.lane === 'M' &&
            p.timeline?.spans.some(s => s.text.includes('Lime Plum Pear Fig Café')))?.timeline;
          await until('five capital tones finish through ordinary Agent Shell navigation without native markers', () => five() &&
            rawPackets.some(p => p.dispatch === five().dispatch_id && p.status === 'completed'));
          const fiveTones = five().actions.filter(a => a.type === 'tone');
          assert.deepEqual(fiveTones.map(a => a.position.utf8_offset), [0, 5, 10, 15, 19]);
          for (const [i, tone] of fiveTones.entries()) assert.ok(rawPackets.some(p => p.lane === 'M' &&
            p.marker?.dispatch_id === five().dispatch_id && p.marker.action_id === tone.id &&
            p.marker.resolution === (i === 0 ? 'exact' : 'word_boundary')));
          // Hold both synthetic output devices while sending two ordinary keys
          // over SSH. Releasing old hardware callbacks must never revive a line.
          controlAudio('N', 'test-permission');
          controlAudio('M', 'test-hold');
          await observe(`(with-selected-window ${phoneWindow} (goto-char (point-min)) (search-forward "Timing start") (beginning-of-line))`);
          const heldStart = rawPackets.length;
          sshKeys('\x0e');
          const navigationAfter = (start, line) => rawPackets.slice(start).find(p =>
            p.lane === 'M' && p.timeline?.spans.map(s => s.text).join('').trim() === line)?.timeline;
          const held = () => navigationAfter(heldStart, 'TestCase');
          await until('first navigation admitted while playback held', held);
          const freshStart = rawPackets.length;
          sshKeys('\x0e');
          const fresh = () => navigationAfter(freshStart, 'Fresh line');
          await until('second navigation cancels the earlier dispatch', () => fresh() &&
            rawPackets.some(p => p.lane === 'M' && p.dispatch === held().dispatch_id && p.status === 'cancelled'));
          controlAudio('M', 'test-play');
          await until('only the later navigation reaches playback completion', () =>
            rawPackets.some(p => p.lane === 'M' && p.dispatch === fresh().dispatch_id && p.status === 'completed'))
            .catch(error => {
              const states = rawPackets.slice(heldStart).filter(p => p.lane === 'M' && (p.timeline || p.dispatch))
                .map(p => p.timeline ? ['admitted', p.timeline.dispatch_id, p.timeline.replacement_key,
                  p.timeline.spans.some(s => s.text.includes('TestCase')), p.timeline.spans.some(s => s.text.includes('Fresh line')),
                  p.timeline.spans.map(s => s.text.length)] : [p.status, p.dispatch]);
              throw new Error(error.message + ' (' + JSON.stringify(states) + ')');
            });
          assert.ok(!rawPackets.some(p => p.marker?.dispatch_id === held().dispatch_id));
          controlAudio('N', 'test-play');
          await until('urgent permission reaches completion on its own output', () => rawPackets.some(p => p.audio === 'permission played'));
          console.log('Passed ordinary Agent Shell Control+n with one TestCase utterance, an in-word insert, semantic playback, replacement and protected permission.');
          await observe(`(with-selected-window ${phoneWindow} (switch-to-buffer iphone-shared-buffer))`);
          const fixture = JSON.parse(fs.readFileSync(path.join(__dirname, '../modules/iphone-mixer/ios/CapitalTiming.json'), 'utf8'));
          const transportTests = path.resolve(__dirname, '../../../test/emacsvox-aural-transport-tests.el');
          await observe(`(load ${JSON.stringify(transportTests)} nil t)`);
          const capitalTimeline = await observe(`(emacsvox-test--with-transport-scheme
            (let ((tts-caps t) (emacsvox-capitalization-presentation 'tone))
              (cl-letf (((symbol-function 'emacsvox-aural-structured-timeline-available-p) (lambda () t)))
                (let* ((text "TestCase") (prepared (emacsvox-aural-prepare-text text nil (emacsvox-test--transport-context)))
                       (plan (emacsvox-aural-concrete-plan-at 0 prepared))
                       (actions (with-temp-buffer (insert prepared) (tts--concrete-positioned-actions (point-min) (point-max)))))
                  (json-serialize (car (emacsvox-aural--build-structured-timeline 1 1 (list (list plan text nil actions)))))))))`);
          assert.deepEqual(JSON.parse(JSON.parse(capitalTimeline)), fixture);
          const before = rawPackets.length;
          sshKeys('\x0e');
          await until('real navigation reaches main worker', () => rawPackets.slice(before).some(p => p.lane === 'M' && p.timeline?.spans.some(span => span.text.trim())));
          await observe(`(with-selected-window ${phoneWindow}
            (switch-to-buffer (get-buffer-create "Phone indentation fixture")) (emacs-lisp-mode)
            (insert "start\n    sample\n        sample\nTestCase\n") (goto-char (point-min))
            (setq-local emacsvox-audio-indentation t emacsvox-indentation-presentation 'duration-tone
                        emacsvox-indentation-tone-timing 'overlay))`);
          function mixedDispatch(start, predicate) {
            return rawPackets.slice(start).some(p => p.lane === 'M' && p.timeline?.spans.some(span => span.text.trim()) &&
              p.timeline.actions?.some(a => a.type === 'tone' && predicate(a)) &&
              rawPackets.some(r => r.lane === 'M' && r.dispatch === p.timeline.dispatch_id && r.status === 'completed'));
          }
          for (const ms of [130, 210]) {
            const start = rawPackets.length;
            sshKeys('\x0e');
            await until('indentation overlay and its spoken line in one dispatch', () => mixedDispatch(start, p =>
              p.mode === 'overlay' && p.frequency_hz === 250 && p.duration_ms === ms));
          }
          await observe(`(with-selected-window ${phoneWindow} (setq-local tts-caps t emacsvox-capitalization-presentation 'tone))`);
          const caps = rawPackets.length;
          sshKeys('\x0e');
          await until('capital insert and its spoken word in one dispatch', () => mixedDispatch(caps, p => p.mode === 'insert'));
          // A printable letter uses the frozen palette on the same worker.
          await observe(`(with-selected-window ${phoneWindow} (beginning-of-line) (forward-char 3))`);
          const spelling = rawPackets.length;
          sshKeys('\x1b[C');
          const letter = () => rawPackets.slice(spelling).find(p => p.lane === 'M' &&
            p.command === 'emacsvox_letter' && p.timeline?.spans.some(s => s.text === 'C'))?.timeline;
          await until('the isolated internal capital reaches playback through the negotiated letter protocol', () =>
            letter() && rawPackets.some(p => p.lane === 'M' && p.dispatch === letter().dispatch_id && p.status === 'completed'));
          assert.equal(letter().protocol_version, 7);
          await observe(`(with-selected-window ${phoneWindow} (switch-to-buffer iphone-shared-buffer)
            (goto-char (point-max))
            (setq-local emacsvox-agent-shell-input-activation 'explicit
                        emacsvox-agent-shell-input-state-feedback 'earcon emacsvox-use-icons t)
            (emacsvox-agent-shell--input-sync))`);
          for (const [keys, file] of [['\x03e', 'off'], ['\r', 'on']]) {
            const cue = fs.readFileSync(path.resolve(__dirname, '../../../sounds/modules/agent-shell/agent-input-' + file + '.ogg'));
            const id = 'omnivox-icon:personal/' + require('node:crypto').createHash('sha256').update(cue).digest('hex');
            const start = rawPackets.length;
            sshKeys(keys);
            await until('Agent Shell ' + file + ' recording on the phone', () =>
              rawPackets.slice(start).some(p => p.lane === 'M' && (p.icon === id || p.timeline?.actions.some(a => a.type === 'audio' && a.path === id))));
          }
          const currentMenu = name => observe(`(and transient--prefix (eq (oref transient--prefix command) '${name}))`);
          await observe(`(setq iphone-test-voices-origin ${phoneWindow})`);
          sshKeys('\x1bxemacsvox-aural-menu\r');
          await until('Aural menu on phone', async () => await currentMenu('emacsvox-aural-menu') === 't');
          sshKeys('v');
          await until('Voices and engines menu on phone', async () => await currentMenu('emacsvox-aural-menu-voices') === 't');
          sshKeys('b');
          const opening = rawPackets.length;
          const inBrowser = () => observe(`(with-selected-window ${phoneWindow}
            (and (derived-mode-p 'iphone-voices-mode) (functionp emacsvox-aural-ui--return-function)))`);
          await until('Browse voices selected with a return to the suspended menu', async () => await inBrowser() === 't');
          assert.equal(await observe(`(eq iphone-test-voices-origin ${phoneWindow})`), 't');
          await until('opening speaks the selected voice on the phone', () =>
            rawPackets.slice(opening).some(p => p.lane === 'M' && p.fixtureRow));
          assert.equal(await observe(`(with-current-buffer (window-buffer ${phoneWindow}) (length tabulated-list-entries))`), '2');
          const row = () => observe(`(with-selected-window ${phoneWindow} (tabulated-list-get-id))`);
          const shown = () => observe(`(with-selected-window ${phoneWindow}
            (and (derived-mode-p 'iphone-voices-mode) (length tabulated-list-entries)))`);
          sshKeys('L');
          await until('language list on the phone frame', async () => await observe(`(with-selected-window ${phoneWindow}
            (derived-mode-p 'emacsvox-voice-languages-mode))`) !== 'nil');
          assert.equal(await observe(`(with-selected-window ${phoneWindow}
            (emacsvox-aural-ui-goto-row "es") (equal (tabulated-list-get-id) "es"))`), 't');
          sshKeys('\r');
          await until('Return stages Spanish on the phone', async () => await observe(`(with-selected-window ${phoneWindow}
            (and (equal emacsvox-voice-languages--selected '("es")) (null emacsvox-voice-browser-languages)))`) === 't');
          sshKeys('q');
          await until('cancel returns to the unfiltered phone browser', async () => await shown() === '2');
          // The disposable -Q profile only applies settings for this session.
          await observe(`(setopt emacsvox-voice-browser-languages '("es"))`);
          await until('Spanish hides both English fixture voices', async () => await shown() === '0');
          await observe('(setopt emacsvox-voice-browser-languages nil)');
          await until('clearing the filter restores both phone voices', async () => await shown() === '2');
          assert.equal(await row(), '"test-1"');
          const movement = rawPackets.length;
          sshKeys('\x0e');
          await until('next phone voice', async () => await row() === '"test-2"');
          await until('voice row speech on the phone', () => rawPackets.slice(movement).some(p => p.lane === 'M' && p.fixtureRow));
          sshKeys('/en-US\t\r');
          await until('find an installed phone voice', async () => await row() === '"test-1"');
          sshKeys('\x0e');
          await until('return to second phone voice', async () => await row() === '"test-2"');
          const startPreview = rawPackets.length;
          sshKeys('P');
          await until('exact preview on the phone main worker', () => rawPackets.slice(startPreview).some(
            p => p.lane === 'M' && p.control === 'preview' && p.voice === 'test-2'));
          assert.ok(!rawPackets.slice(startPreview).some(p => p.lane === 'N' && p.control === 'preview'));
          const voiceAdapter = await observe(`(emacsvox-frame-speech-call (process-get ${main} 'iphone-endpoint)
            (lambda () (list (plist-get (car (plist-get (tts-voice-inventory) :engines)) :engine-id) tts-voice-preview-function)))`);
          assert.equal(voiceAdapter.replace(/\s+/g, ' '), '("ios" omnivox-preview-voice-sequence)');
          sshKeys('t');
          const inEditor = form => observe(`(with-selected-window ${phoneWindow}
            (and (derived-mode-p 'emacsvox-aural-voice-editor-mode) ${form}))`);
          await until('t opens the selected iPhone voice in the common editor', async () =>
            await inEditor(`(equal "test-2" (plist-get (car (plist-get (emacsvox-aural-voice-editor--working) :selectors)) :voice-id))`) === 't');
          assert.notEqual(await inEditor(`(member "reverb" (plist-get (car (plist-get (emacsvox-aural-voice-editor--get :inventory) :engines))
            :post-synthesis-dimensions))`), 'nil');
          const tuned = rawPackets.length;
          sshKeys('P');
          await until('the iPhone auditions this physical choice', () => rawPackets.slice(tuned).some(
            p => p.lane === 'M' && p.previewChoice?.selector.voice_id === 'test-2'));
          await until('the editor receives the iPhone audition result', async () =>
            await inEditor(`(eq 'completed (plist-get (emacsvox-aural-voice-editor--get :preview-result) :status))`) === 't');
          sshKeys('q');
          await until('leaving the tuner restores the iPhone voice row', async () => await row() === '"test-2"');
          sshKeys('\x1bxiphone-test-fallback-editor\r');
          await until('named editor focuses the second physical choice', async () =>
            await inEditor(`(and (button-at (point)) (equal '(choice . 1) (button-get (button-at (point)) 'voice-field)))`) === 't');
          sshKeys('\rCustomize this voice\r');
          await until('only the iPhone fallback is being edited', async () =>
            await inEditor(`(emacsvox-aural-voice-editor--get :tuning-choice)`) === '"phone"');
          for (const [field, level] of [['reverb', 3], ['high-pass', 5], ['low-pass', 5]]) {
            assert.equal(await inEditor(`(progn (emacsvox-aural-voice-editor--locate '${field})
              (and (eq '${field} (button-get (button-at (point)) 'voice-field))
                   (not (string-match-p "unsupported\\\\|not known" (button-label (button-at (point)))))))`), 't');
            await inEditor(`(emacsvox-aural-voice-editor--set '${field} ${level})`);
          }
          const audition = rawPackets.length;
          sshKeys('P');
          const effectChoice = () => rawPackets.slice(audition).find(p => p.lane === 'M' &&
            p.previewChoice?.id === 'phone' && p.previewChoice.selector.voice_id === 'test-2');
          await until('audition targets the second choice on the phone', effectChoice);
          const patch = effectChoice().previewChoice.adjustments;
          for (const [name, stored] of [['reverb', 3], ['high_pass', 5], ['low_pass', 4]]) {
            assert.equal(patch[name].op, 'set');
            assert.ok(Math.abs(patch[name].value - stored / 9) < 0.00001, name);
          }
          await until('the phone confirms the rendered fallback audition', async () =>
            await inEditor(`(eq 'completed (plist-get (emacsvox-aural-voice-editor--get :preview-result) :status))`) === 't');
          assert.equal(await inEditor(`(car (plist-get (emacsvox-aural-voice-editor--get :preview-result) :speech-connection))`),
            await observe(`(process-name ${main})`));
          const picking = rawPackets.length;
          await inEditor(`(emacsvox-aural-voice-editor--locate 'add)`);
          sshKeys('\rtest-2\t\rSearch again\rtest-1\t\rAudition candidate\r');
          await until('the picker auditions the replacement choice through the phone', () =>
            rawPackets.slice(picking).some(p => p.lane === 'M' && p.previewChoice?.id === 'candidate' &&
              p.previewChoice.selector.voice_id === 'test-1'));
          await until('audition leaves the candidate under point with no outstanding prompt', async () =>
            await inEditor(`(and (= 0 (minibuffer-depth)) (eq 'candidate (get-text-property (point) 'voice-field))
              (eq 'completed (plist-get (emacsvox-aural-voice-editor--get :preview-result) :status)))`) === 't');
          sshKeys('qKeep draft and return\r');
          await until('the named fallback returns to the phone browser', async () => await row() === '"test-2"');
          sshKeys('g');
          await until('inventory refreshed on both phone lanes', () => ['M','N'].every(
            lane => rawPackets.slice(startPreview).some(p => p.lane === lane && p.control === 'inventory')));
          assert.equal(await row(), '"test-2"');
          const applying = rawPackets.length;
          sshKeys('\r');
          await until('updated reading voice acknowledged on each worker', () => ['M', 'N'].every(lane => {
            const changes = rawPackets.slice(applying).filter(p => p.lane === lane);
            return changes.some(p => p.control === 'register_logical_voices_v3' && Object.values(p.roleVoices).includes('test-2') &&
              changes.some(r => r.response === 'logical_voices_registered_v3' && r.requestId === p.requestId));
          }));
          sshKeys('/en-US\t\r');
          await until('choose the alternate physical voice', async () => await row() === '"test-1"');
          const roleStart = rawPackets.length;
          sshKeys('rbolden\r');
          await until('both workers acknowledge a distinct voice for bold text', () => ['M', 'N'].every(lane => {
            const changes = rawPackets.slice(roleStart).filter(p => p.lane === lane);
            return changes.some(p => p.roleVoices?.bolden === 'test-1' && Object.values(p.roleVoices).includes('test-2') &&
              changes.some(r => r.response === 'logical_voices_registered_v3' && r.requestId === p.requestId));
          }));
          await observe(`(with-selected-window ${phoneWindow}
            (switch-to-buffer (get-buffer-create "Phone styled line"))
            (text-mode)
            (emacsvox-aural-set-compatibility-voice-enabled t)
            (erase-buffer)
            (insert "Start\n" "plain " (propertize "marble" 'personality 'voice-bolden) " orchard\n")
            (goto-char (point-min)))`);
          const styledStart = rawPackets.length;
          sshKeys('\x0e');
          const styled = () => rawPackets.slice(styledStart).find(p => p.lane === 'M' &&
            p.timeline?.spans.some(s => s.text.includes('marble')))?.timeline;
          await until('styled line completes', () => styled() && rawPackets.slice(styledStart).some(p =>
            p.lane === 'M' && p.dispatch === styled().dispatch_id && p.status === 'completed'));
          const voices = rawPackets.slice(styledStart).filter(p => p.lane === 'M' &&
            p.marker?.dispatch_id === styled().dispatch_id && p.marker.type === 'utterance_started')
            .map(p => [p.marker.text.trim(), p.marker.actual_voice?.voice_id]);
          assert.deepEqual(voices, [['plain','test-2'], ['marble','test-1'], ['orchard','test-2']]);
          await observe(`(with-selected-window ${phoneWindow} (switch-to-buffer (process-get ${main} 'iphone-voice-buffer)))`);
          sshKeys('q');
          await until('quit returns to Voices and engines', async () => await currentMenu('emacsvox-aural-menu-voices') === 't');
          sshKeys('w');
          await until('Resume Voice Workbench opens the phone browser', async () => await inBrowser() === 't');
          sshKeys('q');
          await until('resume returns to the menu', async () => await currentMenu('emacsvox-aural-menu-voices') === 't');
          sshKeys('p');
          await until('Voice palettes opens from the phone menu', async () =>
            await observe(`(with-selected-window ${phoneWindow} (derived-mode-p 'emacsvox-aural-voice-palettes-mode))`) !== 'nil');
          sshKeys('\x1bxomnivox-list-voices\r');
          await until('Omnivox list opens on the phone', async () =>
            await observe(`(with-selected-window ${phoneWindow} (derived-mode-p 'iphone-voices-mode))`) !== 'nil');
          assert.equal(await observe(`(with-selected-window ${phoneWindow} (mapcar #'car (omnivox-refresh-voices)))`),
            '("test-1" "test-2")');
          sshKeys('\x1bxomnivox-select-voice\rFixture  en-US  compact  test-1\r');
          await until('Omnivox Select changes the phone profile', async () =>
            await observe('(plist-get iphone-frame-speech--settings :reading)') === '"test-1"');
          assert.equal(await observe(desktopSnapshot), desktopState);
          ws.send('reset 11');
          await until('raw two-worker Stop response', () => rawPackets.some(p => p.type === 'ready' && p.id === 11));
          const selectedVoice = await row();
          await closeSSH();
          const resumed = await attachSSH(process.env.IPHONE_WIRE_WORKER);
          assert.ok(hasVolume(resumed, 'M', 'tone', 0.5) && hasVolume(resumed, 'N', 'tone', 0.9));
          await until('restored voice browser belongs to the new phone workers', async () =>
            await observe(`(with-selected-window ${phoneWindow}
              (and (derived-mode-p 'iphone-voices-mode) (eq iphone-voices--main ${main})
                   (process-get ${main} 'iphone-routing-ready) (tabulated-list-get-id)))`) === selectedVoice);
          sshKeys('P');
          await until('restored row previews on the replacement worker', () => resumed.some(
            p => p.lane === 'M' && p.control === 'preview' && p.voice === JSON.parse(selectedVoice)));
          sshKeys('/test-2\t\r');
          await until('highlight a voice other than the saved reader', async () => await row() === '"test-2"');
          sshKeys('\x18bPhoneModeFixture\r');
          await until('leave the voice list before disconnecting', async () =>
            await observe(`(buffer-name (window-buffer ${phoneWindow}))`) === '"PhoneModeFixture"');
          await observe(`(with-selected-window ${phoneWindow}
            (switch-to-buffer (iphone-test-render-response "Reconnect start\nUnheard previous row\nFresh after reconnect"))
            (goto-char (point-min)) (search-forward "Reconnect start") (beginning-of-line))`);
          controlAudio('M', 'test-hold');
          sshKeys('\x0e');
          await until('old navigation is admitted before disconnect', () => resumed.some(p =>
            p.timeline?.spans.some(s => s.text.includes('Unheard previous row'))));
          await closeSSH();
          const reconnected = await attachSSH(process.env.IPHONE_WIRE_WORKER);
          await until('fresh phone workers registered after disconnect', async () => await observe(`(process-get ${main} 'iphone-routing-ready)`) === 't');
          sshKeys('\x0e');
          const nextLine = () => reconnected.find(p => p.timeline?.spans.some(s => s.text.includes('Fresh after reconnect')))?.timeline;
          await until('new navigation plays after reconnect', () => nextLine() &&
            reconnected.some(p => p.lane === 'M' && p.dispatch === nextLine().dispatch_id && p.status === 'completed'));
          assert.ok(!reconnected.some(p => p.marker?.text?.includes('Unheard previous row')));
          console.log('Passed disconnect during a held timeline and fresh Control+n on the replacement phone frame.');
          sshKeys('\x1bxomnivox-list-voices\r');
          await until('a fresh browse on the new connection starts on the saved reading voice', async () =>
            await observe(`(with-selected-window ${phoneWindow}
              (and (derived-mode-p 'iphone-voices-mode) (tabulated-list-get-id)))`) === '"test-1"');
          assert.equal(await observe(desktopSnapshot), desktopState);
          await closeSSH();
          console.log('Passed phone voice browsing, preview, Apply, role assignment, palettes and direct voice commands. Control+n used the reading, bold and reading voices within one line.');
        }
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
      assert.equal(await observe("(advice-member-p #'iphone-frame-speech--resource 'omnivox-remote-resource)"), 'nil');
      assert.equal(await observe("(advice-member-p #'iphone-frame-speech--chime 'sox-chime)"), 'nil');
      assert.equal(await observe("(advice-member-p #'iphone-frame-speech--phonetic 'emacsvox--delayed-phonetic-announce)"), 'nil');
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
    fs.rmSync(dir, {recursive: true, force: true, maxRetries: 5, retryDelay: 120});
  }
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
