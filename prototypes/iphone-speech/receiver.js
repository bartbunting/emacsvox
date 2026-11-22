// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later

const speechRate = 1.5;
const eloquenceNames = ['Reed', 'Eddy', 'Rocko', 'Grandpa'];
const openObjectCue = Symbol('open-object');

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
function createReceiver({ speech, cuePlayer, tonePlayer, notificationPlayer, openSocket, status, playback = () => {}, voiceStatus = () => {},
                          keyboard = () => {}, screen = () => {}, sshOffer = () => {}, sessionActive = () => {}, now = Date.now }) {
  let socket, heartbeat, lastReceived, resetId, ready;
  let background = false, resumeOnActive = false, activeBeforeLock = false, retryTimer, frameId;
  let epoch = 0, barrier = Promise.resolve(true), speaking = false;
  let queue = [], queuedChars = 0;
  let voiceLookup, currentRate = speechRate;
  let permission = null;
  const waitingPermissions = new Map();
  const seenPermissions = new Set();
  let cueRequest = 0, cueStarted = false;

  function refreshVoice() {
    const lookup = findVoice(speech).catch(() => null);
    voiceLookup = lookup;
    lookup.then(voice => {
      if (voiceLookup !== lookup) return;
      const label = voice?.label ?? 'iPhone default';
      voiceStatus(label + ' at ' + currentRate + ' times normal speed');
    });
  }

  function stopCue() {
    ++cueRequest;
    if (!cueStarted) return;
    cueStarted = false;
    try { Promise.resolve(cuePlayer.pause()).catch(() => { if (!cueStarted) playback('iOS could not stop the sound.'); }); } catch { playback('iOS could not stop the sound.'); }
  }

  async function playOpenObject() {
    stopCue();
    const owner = cueRequest;
    try {
      if (!cuePlayer?.isLoaded) {
        playback('Open Object sound is still loading.');
        return;
      }
      if (cuePlayer.currentTime > 0) await cuePlayer.seekTo(0, 0, 0);
      if (owner !== cueRequest) return;
      cueStarted = true;
      await cuePlayer.play();
      if (owner !== cueRequest) return;
      playback('Open Object sound requested.');
    } catch {
      if (owner === cueRequest) playback('iOS could not play the Open Object sound.');
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
      while (!urgentText && (queue[0] === openObjectCue || queue[0]?.type === 'tone')) {
        const cue = queue.shift();
        if (cue === openObjectCue) await playOpenObject();
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
      const voice = await voiceLookup;
      if (owner !== notificationGeneration) return;
      await notificationPlayer.speak(text, voice?.identifier ?? null, currentRate);
    } catch { if (owner === notificationGeneration) playback('iOS could not speak the permission request.'); }
    if (owner !== notificationGeneration) return;
    permission = null;
    void speakNotification();
  }

  function stopNotification() {
    ++notificationGeneration;
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
    socket = null;
    resumeOnActive = false;
    activeBeforeLock = false;
    clearTimeout(retryTimer);
    retryTimer = null;
    frameId = null;
    sessionActive(false);
    ready = false;
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
    // Give Tailscale time to resume after unlocking. A manual disconnect or
    // a host-key or authentication error cancels any further attempts.
    function networkFailed(message) {
      const resumeCandidate = activeBeforeLock;
      disconnect(message);
      activeBeforeLock = resumeCandidate;
      if (attempt > 0 && attempt < 4 && !background) {
        status('Waiting for the relay to reconnect');
        sessionActive(true);
        retryTimer = setTimeout(() => connect(attempt + 1), 1000 * attempt);
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
    sessionActive(true);
    resetId = 0;
    lastReceived = now();
    heartbeat = setInterval(() => {
      if (now() - lastReceived > 12000) networkFailed('Connection timed out. Activate Connect to retry.');
      else if (current.readyState === 1) current.send('ping');
    }, 3000);
    current.onmessage = event => {
      if (socket !== current) return;
      let record;
      try { record = JSON.parse(event.data); } catch { disconnect('Invalid relay message'); return; }
      lastReceived = now();
      if (record.type === 'ready' && record.id === resetId) {
        ready = true;
        attempt = 0;
        status('Connected');
        if (record.keyboard === true) {
          keyboard({sendKeys(text) {
            if (socket === current && ready && current.readyState === 1 &&
                typeof text === 'string' && text.length > 0 && text.length <= 256) {
              current.send('key ' + text);
            }
          }});
        }
      } else if (record.type === 'ssh' && typeof record.frame === 'string' &&
                 typeof record.client === 'string' && typeof record.server === 'string') {
        frameId = record.frame;
        sshOffer(record);
      } else if (ready && (record.type === 'permission' || record.type === 'resolved')) {
        permissionRecord(record);
      } else if (record.type === 'screen' && typeof record.text === 'string') {
        screen(record.text);
      } else if (ready && record.type === 'stop') {
        if (record.scope === 'all') clearPermissions();
        if (notificationPlayer || permission === null) silence(record.scope !== 'speech');
        else { queue = []; queuedChars = 0; }
      } else if (ready && record.type === 'cue' && record.name === 'open-object') {
        if (record.immediate) playOpenObject();
        else enqueue(openObjectCue);
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

  function terminalClosed(frame, message) {
    if (frame && frameId === frame) disconnect(message || 'SSH terminal closed. Activate Connect to retry.');
  }

  function stop() {
    clearPermissions();
    silence();
    if (socket?.readyState !== 1) return;
    // Ignore traffic already in flight until the relay clears its pending batch.
    ready = false;
    status('Speech stopped. Waiting for relay.');
    socket.send('reset ' + ++resetId);
  }

  function testVoice(mix = false) {
    clearPermissions();
    silence();
    refreshVoice();
    enqueue(mix ? mixedSample : 'This is the iPhone voice test.');
  }

  function testTone(ms) {
    clearPermissions();
    silence();
    enqueue({type: 'tone', hz: 660, ms});
  }

  return { connect: () => connect(), disconnect, appState, terminalClosed, stop, testTone,
    testVoice: () => testVoice(), testMix: () => testVoice(true), testCue: playOpenObject };
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
