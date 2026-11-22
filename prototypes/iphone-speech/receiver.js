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
function createReceiver({ speech, cuePlayer, openSocket, status, playback = () => {}, voiceStatus = () => {},
                          keyboard = () => {}, screen = () => {}, now = Date.now }) {
  let socket, heartbeat, lastReceived, resetId, ready;
  let epoch = 0, barrier = Promise.resolve(true), speaking = false;
  let queue = [], queuedChars = 0;
  let voiceLookup;
  let cueRequest = 0, cueStarted = false;

  function refreshVoice() {
    const lookup = findVoice(speech).catch(() => null);
    voiceLookup = lookup;
    lookup.then(voice => {
      if (voiceLookup !== lookup) return;
      const label = voice?.label ?? 'iPhone default';
      voiceStatus(label + ' at ' + speechRate + ' times normal speed');
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
    if (includeSound) stopCue();
  }

  function drain() {
    if (speaking || !queue.length) return;
    speaking = true;
    const owner = epoch;
    barrier.then(async result => {
      if (owner !== epoch || !result) return;
      // Queued sound starts at its place in the dispatch and can overlap speech.
      while (queue[0] === openObjectCue) {
        queue.shift();
        await playOpenObject();
        if (owner !== epoch) return;
      }
      if (!queue.length) {
        speaking = false;
        return;
      }
      const voice = await voiceLookup;
      if (owner !== epoch) return;
      const item = queue.shift();
      const mix = item === mixedSample;
      const text = mix ? 'This is the mixer test. The lighthouse keeper climbed the stairs to light the lamp.' : item;
      if (!mix) queuedChars -= text.length;
      const finish = state => {
        if (owner !== epoch) return;
        playback(state);
        speaking = false;
        drain();
      };
      speech.speak(text, {
        ...(voice && { voice: voice.identifier }),
        ...(mix && { mixSample: true }),
        rate: speechRate,
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
    const chars = typeof item === 'string' ? item.length : 0;
    if (queuedChars + chars > 1_000_000 || queue.length >= 1024) {
      disconnect('Speech queue full. Activate Connect to retry.');
      return;
    }
    queue.push(item);
    queuedChars += chars;
    if (chars) playback('Speech queued.');
    drain();
  }

  function disconnect(message = 'Disconnected') {
    const old = socket;
    socket = null;
    ready = false;
    keyboard(null);
    screen('');
    clearInterval(heartbeat);
    silence();
    old?.close();
    status(message);
  }

  function connect() {
    disconnect('Connecting');
    refreshVoice();
    let current;
    try {
      current = openSocket();
    } catch {
      disconnect('Connection failed. Check Tailscale and the relay.');
      return;
    }
    socket = current;
    resetId = 0;
    lastReceived = now();
    heartbeat = setInterval(() => {
      if (now() - lastReceived > 12000) disconnect('Connection timed out. Activate Connect to retry.');
      else if (current.readyState === 1) current.send('ping');
    }, 3000);
    current.onmessage = event => {
      if (socket !== current) return;
      let record;
      try { record = JSON.parse(event.data); } catch { disconnect('Invalid relay message'); return; }
      lastReceived = now();
      if (record.type === 'ready' && record.id === resetId) {
        ready = true;
        status('Connected');
        if (record.keyboard === true) {
          keyboard({sendKeys(text) {
            if (socket === current && ready && current.readyState === 1 &&
                typeof text === 'string' && text.length > 0 && text.length <= 256) {
              current.send('key ' + text);
            }
          }});
        }
      } else if (record.type === 'screen' && typeof record.text === 'string') {
        screen(record.text);
      } else if (ready && record.type === 'stop') {
        silence(record.scope !== 'speech');
      } else if (ready && record.type === 'cue' && record.name === 'open-object') {
        if (record.immediate) playOpenObject();
        else enqueue(openObjectCue);
      } else if (ready && ['letter', 'speak'].includes(record.type) && typeof record.text === 'string') {
        enqueue(record.type === 'letter' ? characterName(record.text) : record.text);
      }
    };
    current.onclose = current.onerror = () => {
      if (socket === current) disconnect('Disconnected. Activate Connect to retry.');
    };
  }

  function stop() {
    silence();
    if (socket?.readyState !== 1) return;
    // Ignore traffic already in flight until the relay clears its pending batch.
    ready = false;
    status('Speech stopped. Waiting for relay.');
    socket.send('reset ' + ++resetId);
  }

  function testVoice(mix = false) {
    silence();
    refreshVoice();
    enqueue(mix ? mixedSample : 'This is the iPhone voice test.');
  }

  return { connect, disconnect, stop, testVoice: () => testVoice(), testMix: () => testVoice(true), testCue: playOpenObject };
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
