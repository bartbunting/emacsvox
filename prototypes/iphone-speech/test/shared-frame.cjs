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
      // Mode-line feedback can invoke SoX directly even with a test speech backend.
      env: {...process.env, AUDIODRIVER: 'alsa', AUDIODEV: 'null', GDK_BACKEND: 'x11',
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
        async function attachSSH(rawWorker) {
          const packets = [];
          ws = new WebSocket('ws://127.0.0.1:' + sshRelay.httpServer.address().port + '/speech/ssh' + (rawWorker ? '/omnivox' : ''));
          const current = ws, workers = {};
          if (rawWorker) {
            for (const tag of ['M', 'N']) {
              const worker = spawn(rawWorker, [], {stdio: ['pipe', 'pipe', 'inherit']});
              workers[tag] = worker;
              require('node:readline').createInterface({input: worker.stdout}).on('line', line => {
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
              packets.push({lane: message[0], command: line.split(' ')[0], icon: icon?.[1],
                control: control?.type, voice: control?.selector?.voice_id,
                fixtureRow: /^q\s/.test(line) && line.includes('Fixture'),
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
        await observe('(with-selected-window ' + phoneWindow + ' (switch-to-buffer iphone-shared-buffer) (goto-char ' + beforeKeys + '))');
        console.log('Passed Meta buffer boundaries and both Control+Meta inputs through the Swift SSH client to Emacs.');
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
          const rawPackets = await attachSSH(process.env.IPHONE_WIRE_WORKER);
          const phone = `(window-frame ${phoneWindow})`;
          const main = `(frame-parameter ${phone} 'emacsvox-phone-speaker)`;
          const notification = `(process-get ${main} 'iphone-notify)`;
          await until('both Omnivox workers discovered and registered', async () =>
            await observe(`(cl-every (lambda (p) (and (equal "ios" (plist-get (process-get p omnivox--control-inventory-property) :preferred_engine_id))
              (process-get p omnivox--control-registration-property))) (list ${main} ${notification}))`) === 't', 30000);
          const desktopSnapshot = '(list (process-name tts-speaker-process) omnivox-engine-inventory omnivox-available-voices omnivox-default-voice-id)';
          const desktopState = await observe(desktopSnapshot);
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
          await until('real navigation reaches main worker', () => rawPackets.slice(before).some(p => p.lane === 'M' && p.command === 'q'));
          await observe(`(with-selected-window ${phoneWindow}
            (switch-to-buffer (get-buffer-create "Phone indentation fixture")) (emacs-lisp-mode)
            (insert "start\n    sample\n        sample\nTestCase\n") (goto-char (point-min))
            (setq-local emacsvox-audio-indentation t emacsvox-indentation-presentation 'duration-tone
                        emacsvox-indentation-tone-timing 'overlay))`);
          function mixedDispatch(start, predicate) {
            const main = rawPackets.slice(start).filter(p => p.lane === 'M');
            const at = main.findIndex(predicate);
            if (at < 0) return false;
            const rest = main.slice(at + 1);
            const end = rest.findIndex(p => ['s', 'd', 'emacsvox_tracked_dispatch'].includes(p.command));
            return end >= 0 && rest[end].command !== 's' && rest.slice(0, end).some(p => p.command === 'q');
          }
          for (const ms of [130, 210]) {
            const start = rawPackets.length;
            sshKeys('\x0e');
            await until('indentation overlay and its spoken line in one dispatch', () => mixedDispatch(start, p =>
              p.tone?.mode === 'overlay' && p.tone.hz === 250 && p.tone.ms === ms));
          }
          await observe(`(with-selected-window ${phoneWindow} (setq-local tts-caps t emacsvox-capitalization-presentation 'tone))`);
          const caps = rawPackets.length;
          sshKeys('\x0e');
          await until('capital insert and its spoken word in one dispatch', () => mixedDispatch(caps, p => p.tone?.mode === 'insert'));
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
              rawPackets.slice(start).some(p => p.icon === id && p.lane === 'M'));
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
          sshKeys('g');
          await until('inventory refreshed on both phone lanes', () => ['M','N'].every(
            lane => rawPackets.slice(startPreview).some(p => p.lane === lane && p.control === 'inventory')));
          assert.equal(await row(), '"test-2"');
          sshKeys('\r');
          await until('reading voice applied to both lanes', async () => await observe(`(cl-every
            (lambda (p) (seq-some (lambda (b) (equal "test-2" (plist-get (plist-get (plist-get b :resolution) :realized) :voice_id)))
                                  (plist-get (plist-get (process-get p omnivox--control-registration-property) :registration) :bindings)))
            (list ${main} ${notification}))`) === 't');
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
          await closeSSH();
          await attachSSH(process.env.IPHONE_WIRE_WORKER);
          sshKeys('\x1bxomnivox-list-voices\r');
          await until('a fresh browse on the new connection starts on the saved reading voice', async () =>
            await observe(`(with-selected-window ${phoneWindow}
              (and (derived-mode-p 'iphone-voices-mode) (tabulated-list-get-id)))`) === '"test-1"');
          assert.equal(await observe(desktopSnapshot), desktopState);
          await closeSSH();
          console.log('Passed phone Settings browse, find, exact preview, refresh, Apply, return, resume, palettes and direct voice commands with desktop speech isolated.');
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
