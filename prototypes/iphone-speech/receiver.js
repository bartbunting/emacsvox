// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later

const {openWire} = require('./wire-receiver');
const {isWebLink} = require('./web-link');

const speechRate = 1.5;
const eloquenceNames = ['Reed', 'Eddy', 'Rocko', 'Grandpa'];

const mixedSample = Symbol('mixed audio test');

async function findVoice(speech) {
  const voices = await speech.getAvailableVoicesAsync();
  const english = voices.filter(voice => voice.identifier && /^en(?:[-_]|$)/i.test(voice.language));
  for (const name of [...eloquenceNames, 'Daniel', 'Aaron', 'Lee']) {
    // iOS can append the language in parentheses to the display name.
    const matches = english.filter(voice => voice.name.split(' (')[0].toLowerCase() === name.toLowerCase());
    const voice = matches.find(v => /^en[-_]US$/i.test(v.language)) ?? matches[0];
    if (voice) {
      const label = eloquenceNames.includes(name) ? 'Eloquence ' + name : name;
      return { identifier: voice.identifier, label };
    }
  }
  return null;
}

// All speech for the foreground receiver belongs to this instance. The epoch
// invalidates delayed native callbacks as well as already received dispatches.
function createReceiver({ speech, cuePlayer, visualLinePlayer, tonePlayer, notificationPlayer, nativeWire, openSocket, status, playback = () => {}, voiceStatus = () => {},
                          keyboard = () => {}, screen = () => {}, sshOffer = () => {}, openWebLink, sessionActive = () => {},
                          connectionResult = () => {}, now = Date.now }) {
  let wire, socket, heartbeat, lastReceived, resetId, ready;
  let traceAllowed = false, tracePending = false, timingAllowed = false;
  let browserReady = false;
  let background = false, resumeOnActive = false, activeBeforeLock = false, retryTimer, frameId;
  let retryNetworkLoss, sessionEstablished = false;
  let sshKeyboardConnected = false, sshKeyboardPublished = false;
  let epoch = 0, barrier = Promise.resolve(true), speaking = false;
  let queue = [], queuedChars = 0;
  let voiceLookup, currentRate = speechRate;
  let permission = null;
  const waitingPermissions = new Map();
  const seenPermissions = new Set();
  const openObjectCue = {type: 'cue', player: cuePlayer, label: 'Open Object'};
  const visualLineCue = {type: 'cue', player: visualLinePlayer, label: 'Visual line'};
  let cueRequest = 0, activeCuePlayer;

  function refreshVoice() {
    const lookup = findVoice(speech).catch(() => null);
    voiceLookup = lookup;
    lookup.then(voice => {
      if (voiceLookup !== lookup) return;
      if (nativeWire) { voiceStatus('Omnivox on iPhone. Open the Emacs voice workbench to select a voice.'); return; }
      const label = voice?.label ?? 'iPhone default';
      voiceStatus(label + ' at ' + currentRate + ' times normal speed');
    });
  }

  function stopCue() {
    ++cueRequest;
    const player = activeCuePlayer;
    if (!player) return;
    activeCuePlayer = undefined;
    try { Promise.resolve(player.pause()).catch(() => { if (!activeCuePlayer) playback('iOS could not stop the sound.'); }); } catch { playback('iOS could not stop the sound.'); }
  }

  async function playCue({player, label}) {
    stopCue();
    const owner = cueRequest;
    try {
      if (!player?.isLoaded) {
        playback(label + ' sound is still loading.');
        return;
      }
      if (player.currentTime > 0) await player.seekTo(0, 0, 0);
      if (owner !== cueRequest) return;
      activeCuePlayer = player;
      await player.play();
      if (owner !== cueRequest) return;
      playback(label + ' sound requested.');
    } catch {
      if (owner === cueRequest) playback('iOS could not play the ' + label + ' sound.');
    }
  }

  function silence(includeSound = true) {
    const owner = ++epoch;
    queue = [];
    queuedChars = 0;
    speaking = false;
    // An idle AVSpeechSynthesizer can return false from stopSpeaking.
    // Any fulfilled stop permits fresh speech. Only rejection blocks it.
    barrier = speech.stop(includeSound).then(() => true, () => {
      if (epoch === owner) playback('iOS could not stop speech.');
      return false;
    });
    if (includeSound) {
      stopCue();
      if (tonePlayer) Promise.resolve(tonePlayer.stop()).catch(() => {});
    }
  }

  function drain() {
    if (speaking) return;
    let urgentText;
    if (!notificationPlayer && waitingPermissions.size) {
      const [id, words] = waitingPermissions.entries().next().value;
      waitingPermissions.delete(id);
      permission = id;
      urgentText = words;
    }
    if (!urgentText && !queue.length) return;
    speaking = true;
    const owner = epoch;
    barrier.then(async result => {
      if (owner !== epoch || !result) return;
      // Queued sound starts at its place in the dispatch and can overlap speech.
      while (!urgentText && (queue[0]?.type === 'cue' || queue[0]?.type === 'tone')) {
        const cue = queue.shift();
        if (cue.type === 'cue') await playCue(cue);
        else if (tonePlayer) {
          try {
            await tonePlayer.prepare();
            if (owner !== epoch) return;
            await tonePlayer.play(cue.hz, cue.ms);
          } catch { if (owner === epoch) playback('iOS could not play the tone.'); }
        }
        if (owner !== epoch) return;
      }
      if (!urgentText && !queue.length) {
        speaking = false;
        return;
      }
      const voice = await voiceLookup;
      if (owner !== epoch) return;
      const item = urgentText ?? queue.shift();
      const mix = item === mixedSample;
      const text = mix ? 'This is the mixer test. The lighthouse keeper climbed the stairs to light the lamp.' : (item.text ?? item);
      if (!mix && !urgentText) queuedChars -= text.length;
      const finish = state => {
        if (owner !== epoch) return;
        playback(state);
        if (!notificationPlayer) permission = null;
        speaking = false;
        drain();
      };
      speech.speak(text, {
        ...(voice && { voice: voice.identifier }),
        ...(mix && { mixSample: true }),
        rate: item.rate ?? currentRate,
        useApplicationAudioSession: false,
        onStart: () => {
          if (owner === epoch) playback('iOS started speech.');
        },
        onDone: () => finish('iOS finished speech.'),
        onStopped: () => finish('iOS stopped speech.'),
        onError: () => finish('iOS could not speak this utterance.'),
      });
    });
  }

  function enqueue(item) {
    if (!item) return;
    const chars = typeof item === 'string' ? item.length : (item.text?.length ?? 0);
    if (queuedChars + chars > 1_000_000 || queue.length >= 1024) {
      disconnect('Speech queue full. Activate Connect to retry.');
      return;
    }
    queue.push(item);
    queuedChars += chars;
    if (chars) playback('Speech queued.');
    drain();
  }

  let notificationGeneration = 0;

  async function speakNotification() {
    if (!notificationPlayer || permission !== null || !waitingPermissions.size) return;
    const [id, text] = waitingPermissions.entries().next().value;
    const owner = ++notificationGeneration;
    waitingPermissions.delete(id);
    permission = id;
    try {
      if (wire) await wire.permission(text);
      else {
        const voice = await voiceLookup;
        if (owner !== notificationGeneration) return;
        await notificationPlayer.speak(text, voice?.identifier ?? null, currentRate);
      }
    } catch { if (owner === notificationGeneration) playback('iOS could not speak the permission request.'); }
    if (owner !== notificationGeneration) return;
    permission = null;
    void speakNotification();
  }

  function stopNotification() {
    ++notificationGeneration;
    if (permission !== null) wire?.stopPermission();
    permission = null;
    if (notificationPlayer) Promise.resolve(notificationPlayer.stop()).catch(() => {});
  }

  function clearPermissions() {
    stopNotification();
    waitingPermissions.clear();
  }

  function permissionRecord(record) {
    if (typeof record.id !== 'string') return;
    if (record.type === 'resolved') {
      waitingPermissions.delete(record.id);
      seenPermissions.delete(record.id);
      if (permission === record.id) {
        stopNotification();
        if (notificationPlayer) void speakNotification();
        else { silence(); drain(); }
      }
    } else if (!seenPermissions.has(record.id) && typeof record.text === 'string' && record.text) {
      if (seenPermissions.size >= 256) return disconnect('Too many pending requests. Reconnect to refresh.');
      seenPermissions.add(record.id);
      waitingPermissions.set(record.id, record.text);
      if (notificationPlayer) void speakNotification();
      else {
        if (permission === null) silence();
        drain();
      }
    }
  }

  function disconnect(message = 'Disconnected') {
    const old = socket;
    wire?.close();
    wire = null;
    socket = null;
    resumeOnActive = false;
    activeBeforeLock = false;
    clearTimeout(retryTimer);
    retryTimer = null;
    retryNetworkLoss = null;
    sessionEstablished = false;
    frameId = null;
    sshKeyboardConnected = sshKeyboardPublished = false;
    sessionActive(false);
    ready = false;
    traceAllowed = tracePending = timingAllowed = false;
    browserReady = false;
    keyboard(null);
    sshOffer(null);
    clearPermissions();
    seenPermissions.clear();
    screen('');
    clearInterval(heartbeat);
    silence();
    old?.close();
    status(message);
  }

  function connect(attempt = 0) {
    if (background) return;
    disconnect(attempt ? 'Reconnecting' : 'Connecting');
    currentRate = speechRate;
    refreshVoice();
    // A fresh connection never reuses the previous audio queue or SSH frame.
    function networkFailed(message, retryStatus = 'Waiting for the relay to reconnect') {
      if (!frameId) connectionResult(message);
      const resumeCandidate = activeBeforeLock;
      const canRetry = sessionEstablished || Boolean(frameId) || attempt > 0;
      const next = sessionEstablished ? 1 : attempt + 1;
      disconnect(message);
      activeBeforeLock = resumeCandidate;
      if (canRetry && next <= 4 && !background) {
        status(retryStatus);
        sessionActive(true);
        retryTimer = setTimeout(() => connect(next), 1000 * Math.max(1, next - 1));
      }
    }
    let current;
    try {
      current = openSocket();
    } catch {
      networkFailed('Connection failed. Check Tailscale and the relay.');
      return;
    }
    socket = current;
    retryNetworkLoss = networkFailed;
    sessionActive(true);
    resetId = 0;
    lastReceived = now();
    heartbeat = setInterval(() => {
      if (now() - lastReceived > 12000) networkFailed('Connection timed out. Activate Connect to retry.');
      else if (current.readyState === 1) current.send('ping');
    }, 3000);
    current.onmessage = event => {
      if (socket !== current) return;
      if (wire && typeof event.data === 'string' && /^[MN] /.test(event.data)) {
        lastReceived = now();
        wire.record(event.data, !ready);
        return;
      }
      let record;
      try { record = JSON.parse(event.data); } catch { disconnect('Invalid relay message'); return; }
      lastReceived = now();
      if (record.type === 'discovering' && nativeWire) {
        status('Finding iPhone voices');
      } else if (record.type === 'ready' && record.id === resetId) {
        ready = true;
        if (record.speechTrace === true) traceAllowed = true;
        timingAllowed = record.keyTiming === true;
        if (wire && openWebLink && record.browseUrl === true && !browserReady) {
          browserReady = true;
          current.send('browser-ready');
        }
        if (!frameId || sshKeyboardConnected) sessionEstablished = true;
        status('Connected');
        if (record.keyboard === true) {
          keyboard({sendKeys(text) {
            if (socket === current && ready && current.readyState === 1 &&
                typeof text === 'string' && text.length > 0 && text.length <= 256) {
              current.send('key ' + text);
            }
          }});
        } else publishSshKeyboard();
      } else if (record.type === 'trace-saved' && tracePending) {
        tracePending = false;
        playback(record.ok === true ? 'Speech trace saved in WSL.' : 'WSL could not save the speech trace.');
      } else if (record.type === 'ssh' && typeof record.frame === 'string' &&
                 typeof record.client === 'string' && typeof record.server === 'string') {
        if (frameId) return disconnect('Unexpected second SSH offer.');
        frameId = record.frame;
        if (nativeWire) {
          wire = openWire(nativeWire, line => {
            if (socket === current && current.readyState === 1) current.send(line);
          }, () => disconnect('iPhone speech worker failed. Reconnect to retry.'));
          wire.opened.then(() => { if (socket === current) sshOffer(record); },
            () => { if (socket === current) disconnect('Could not open the local Omnivox workers.'); });
        } else sshOffer(record);
      } else if (record.type === 'open-url') {
        if (ready && browserReady && !background && record.frame === frameId && isWebLink(record.url)) {
          Promise.resolve().then(() => {
            if (ready && socket === current && frameId === record.frame && !background) return openWebLink(frameId, record.url);
          }).catch(() => { if (socket === current) playback('The iPhone could not open the web link.'); });
        }
      } else if (ready && (record.type === 'permission' || record.type === 'resolved')) {
        permissionRecord(record);
      } else if (record.type === 'screen' && typeof record.text === 'string') {
        screen(record.text);
      } else if (ready && record.type === 'stop') {
        if (record.scope === 'all') { clearPermissions(); wire?.stop(); }
        if (notificationPlayer || permission === null) silence(record.scope !== 'speech');
        else { queue = []; queuedChars = 0; }
      } else if (ready && ((record.type === 'cue' && record.name === 'open-object') ||
                 (record.type === 'speak' && record.cue === 'visual-line' && visualLinePlayer?.isLoaded))) {
        const cue = record.type === 'cue' ? openObjectCue : visualLineCue;
        if (record.immediate) void playCue(cue);
        else enqueue(cue);
      } else if (ready && record.type === 'tone' && tonePlayer) {
        enqueue(record);
      } else if (ready && ['letter', 'speak'].includes(record.type) && typeof record.text === 'string') {
        const text = record.type === 'letter' ? characterName(record.text) : record.text;
        if (Number.isFinite(record.rate) && record.rate >= 0 && record.rate <= 2 && currentRate !== record.rate) {
          currentRate = record.rate;
          const rate = currentRate;
          voiceLookup.then(v => { if (socket === current && currentRate === rate)
            voiceStatus((v?.label ?? 'iPhone default') + ' at ' + rate + ' times normal speed'); });
        }
        if (text) enqueue({text, rate: currentRate});
      }
    };
    current.onclose = current.onerror = () => {
      if (socket === current) networkFailed('Disconnected. Activate Connect to retry.');
    };
  }

  function appState(state) {
    if (state === 'inactive' && !background) {
      activeBeforeLock ||= Boolean(socket || retryTimer);
    } else if (state === 'background' && !background) {
      background = true;
      const resume = Boolean(socket || retryTimer || activeBeforeLock);
      disconnect(resume ? 'Paused until you return' : 'Disconnected');
      resumeOnActive = resume;
    } else if (state === 'active') {
      activeBeforeLock = false;
      background = false;
      if (resumeOnActive) connect(1);
    }
  }

  function publishSshKeyboard() {
    if (ready && sshKeyboardConnected && !sshKeyboardPublished) {
      sshKeyboardPublished = true;
      keyboard({frame: frameId});
    }
  }

  function terminalConnected(frame) {
    if (!frame || frame !== frameId || sshKeyboardConnected) return;
    connectionResult('SSH terminal opened.');
    sshKeyboardConnected = true;
    if (ready) sessionEstablished = true;
    publishSshKeyboard();
  }

  function terminalClosed(frame, message, retryable = false) {
    if (!frame || frameId !== frame) return;
    const detail = message || 'SSH terminal closed. Activate Connect to retry.';
    connectionResult(message || 'SSH terminal closed.');
    if (retryable && retryNetworkLoss) retryNetworkLoss(detail, (message || 'SSH terminal closed.') + ' Retrying SSH.');
    else disconnect(detail);
  }

  function stop() {
    wire?.stop();
    clearPermissions();
    silence();
    if (socket?.readyState !== 1) return;
    // Ignore traffic already in flight until the relay clears its pending batch.
    ready = false;
    status('Speech stopped. Waiting for relay.');
    socket.send('reset ' + ++resetId);
  }

  function localWireTest(sound) {
    const owner = wire;
    if (!owner) return false;
    owner.test(sound).then(ok => {
      if (owner === wire) playback(typeof ok === 'string' ? ok : ok ? 'Omnivox finished playback.' : 'Omnivox playback stopped.');
    }, () => { if (owner === wire) playback('Omnivox could not play the sample.'); });
    return true;
  }

  function sendSpeechTrace() {
    if (!wire || !ready || socket?.readyState !== 1) return playback('Connect to WSL to send the speech trace.');
    if (!traceAllowed) return playback('This relay needs an update to receive speech traces.');
    if (tracePending) return playback('Waiting for WSL to save the trace.');
    const text = nativeWire.speechTrace();
    if (!text) return playback('The speech trace is empty.');
    try {
      socket.send('speech-trace ' + text);
      tracePending = true;
      playback('Sending speech trace to WSL.');
    } catch { playback('Could not send the speech trace.'); }
  }

  function testVoice(mix = false) {
    if (localWireTest('voice')) return;
    clearPermissions();
    silence();
    refreshVoice();
    enqueue(mix ? mixedSample : 'This is the iPhone voice test.');
  }

  function testTone(ms) {
    if (localWireTest(ms === 480 ? 'short' : 'long')) return;
    clearPermissions();
    silence();
    enqueue({type: 'tone', hz: 660, ms});
  }

  return { connect: () => connect(), disconnect, appState, terminalConnected, terminalClosed, stop, testTone,
    async prepareKeyTiming(frame, local) {
      if (!wire || !ready || !sshKeyboardConnected || frameId !== frame) throw new Error('Connect the SSH terminal first.');
      if (!local && !timingAllowed) throw new Error('The connected Emacs frame does not offer the timing test.');
      return wire.prepareTiming(local);
    },
    cancelKeyTiming: () => wire?.cancelTiming(),
    testMarkers: () => localWireTest('markers'), lastTiming: () => localWireTest('last-timing'), sendSpeechTrace,
    testVoice: () => testVoice(), testMix: () => testVoice(true), testCue: () => localWireTest('accent') || playCue(openObjectCue),
    testVisualLine: () => localWireTest('chime') || playCue(visualLineCue) };
}

const symbols = {
  ' ': 'space', '!': 'exclamation mark', '"': 'double quote', '#': 'hash',
  '$': 'dollar', '%': 'percent', '&': 'ampersand', "'": 'apostrophe',
  '(': 'left parenthesis', ')': 'right parenthesis', '*': 'asterisk',
  '+': 'plus', ',': 'comma', '-': 'hyphen', '.': 'period', '/': 'slash',
  ':': 'colon', ';': 'semicolon', '<': 'less than', '=': 'equals',
  '>': 'greater than', '?': 'question mark', '@': 'at', '[': 'left bracket',
  '\\': 'backslash', ']': 'right bracket', '^': 'caret', '_': 'underscore',
  '`': 'backtick', '{': 'left brace', '|': 'vertical bar', '}': 'right brace',
  '~': 'tilde',
};
function characterName(text) {
  if (Object.hasOwn(symbols, text)) return symbols[text];
  return /^[A-Z]$/.test(text) ? 'capital ' + text : text;
}

module.exports = { createReceiver };
