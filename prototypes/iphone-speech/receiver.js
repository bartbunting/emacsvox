// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later

// All speech for the foreground receiver belongs to this instance. The epoch
// invalidates delayed native callbacks as well as already received dispatches.
function createReceiver({ speech, openSocket, status, playback = () => {}, now = Date.now }) {
  let socket, heartbeat, lastReceived, resetId, ready;
  let epoch = 0, barrier = Promise.resolve(true), speaking = false;
  let queue = [], queuedChars = 0;

  function silence() {
    const owner = ++epoch;
    queue = [];
    queuedChars = 0;
    speaking = false;
    // An idle AVSpeechSynthesizer can return false from stopSpeaking.
    // Any fulfilled stop permits fresh speech. Only rejection blocks it.
    barrier = speech.stop().then(() => true, () => {
      if (epoch === owner) playback('iOS could not stop speech.');
      return false;
    });
  }

  function drain() {
    if (speaking || !queue.length) return;
    speaking = true;
    const owner = epoch;
    barrier.then(result => {
      if (owner !== epoch || !result) return;
      const text = queue.shift();
      queuedChars -= text.length;
      const finish = state => {
        if (owner !== epoch) return;
        playback(state);
        speaking = false;
        drain();
      };
      speech.speak(text, {
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

  function enqueue(text) {
    if (!text) return;
    if (queuedChars + text.length > 1_000_000 || queue.length >= 1024) {
      disconnect('Speech queue full. Activate Connect to retry.');
      return;
    }
    queue.push(text);
    queuedChars += text.length;
    playback('Speech queued.');
    drain();
  }

  function disconnect(message = 'Disconnected') {
    const old = socket;
    socket = null;
    ready = false;
    clearInterval(heartbeat);
    silence();
    old?.close();
    status(message);
  }

  function connect() {
    disconnect('Connecting');
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
      } else if (ready && record.type === 'stop') {
        silence();
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

  function testVoice() {
    silence();
    enqueue('This is the iPhone voice test.');
  }

  return { connect, disconnect, stop, testVoice };
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
