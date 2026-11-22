// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later

const test = require('node:test');
const assert = require('node:assert/strict');
const { createReceiver } = require('../receiver');
const flush = () => new Promise(resolve => setImmediate(resolve));

test('native stop races, stalled socket and delayed callbacks after reconnect', async () => {
  const sockets = [], stops = [], spoken = [];
  const receiver = createReceiver({
    status() {},
    openSocket() {
      const socket = { readyState:1, send(cmd) { this.sent = cmd; }, close() {} };
      sockets.push(socket);
      return socket;
    },
    speech: {
      stop: () => new Promise(resolve => stops.push(resolve)),
      speak: (text, callbacks) => spoken.push({text, callbacks}),
    },
  });
  const send = (record, socket = sockets.at(-1)) => socket.onmessage({data:JSON.stringify(record)});
  const release = async () => { stops.splice(0).forEach(done => done()); await flush(); };
  try {
    receiver.connect();
    send({type:'ready', id:0});
    send({type:'speak', text:'old'});
    await release();
    send({type:'stop'});
    send({type:'speak', text:'middle'});
    send({type:'stop'});
    send({type:'speak', text:'next'});
    spoken[0].callbacks.onStopped();
    await release();
    assert.deepEqual(spoken.map(x => x.text), ['old','next']);
    receiver.stop();
    assert.equal(stops.length, 1);
    assert.equal(sockets[0].sent, 'reset 1');
    send({type:'speak', text:'in flight'});
    await release();
    send({type:'ready', id:1});
    send({type:'letter', text:'.'});
    await flush();
    receiver.disconnect();
    receiver.connect();
    send({type:'ready', id:0});
    send({type:'speak', text:'after reconnect'});
    send({type:'speak', text:'late'}, sockets[0]);
    sockets[0].onclose();
    await release();
    assert.deepEqual(spoken.map(x => x.text), ['old','next','period','after reconnect']);
  } finally {
    receiver.disconnect();
  }
});

test('an idle iOS stop permits the next dispatched line', async () => {
  const spoken = [];
  const socket = {readyState: 1, close() {}};
  const receiver = createReceiver({
    status() {},
    openSocket: () => socket,
    speech: {stop: async () => false, speak: text => spoken.push(text)},
  });
  try {
    receiver.connect();
    for (const message of [{type:'ready', id:0}, {type:'stop'}, {type:'speak', text:'Sample line'}]) {
      socket.onmessage({data: JSON.stringify(message)});
    }
    await flush();
    assert.deepEqual(spoken, ['Sample line']);
  } finally {
    receiver.disconnect();
  }
});

test('local voice test works without a socket and reports native callbacks', async () => {
  const states = [];
  let utterance;
  const receiver = createReceiver({
    status() {}, playback: state => states.push(state),
    openSocket: () => assert.fail('Local voice test opened a connection'),
    speech: {stop: async () => false, speak: (text, options) => { utterance = {text, options}; }},
  });
  receiver.testVoice();
  await flush();
  assert.equal(utterance.text, 'This is the iPhone voice test.');
  utterance.options.onStart();
  utterance.options.onDone();
  assert.deepEqual(states.slice(-2), ['iOS started speech.', 'iOS finished speech.']);
});

test('navigation, character and preview use the phone’s English Reed at the faster rate', async () => {
  const voices = [
    {name:'Daniel', language:'en-GB', identifier:'daniel'},
    {name:'Reed', language:'fr-FR', identifier:'french'},
    {name:'Reed (English (UK))', language:'en-GB', identifier:'british'},
    {name:'Reed (English (US))', language:'en-US', identifier:'installed-us-reed'},
  ];
  const spoken = [], labels = [];
  const socket = { readyState:1, close() {} };
  const receiver = createReceiver({
    status() {}, voiceStatus: value => labels.push(value), openSocket: () => socket,
    speech: {stop: async () => false, getAvailableVoicesAsync: async () => voices,
      speak: (text, options) => spoken.push(options)},
  });
  try {
    receiver.connect();
    const send = record => socket.onmessage({data:JSON.stringify(record)});
    send({type:'ready', id:0});
    send({type:'speak', text:'Navigation'});
    await flush();
    send({type:'stop'});
    send({type:'letter', text:'X'});
    await flush();
    receiver.testVoice();
    await flush();
    assert.equal(spoken.length, 3);
    for (const options of spoken) {
      assert.equal(options.voice, 'installed-us-reed');
      assert.equal(options.rate, 1.5);
    }
    assert.ok(labels.includes('Eloquence Reed at 1.5 times normal speed'));
  } finally { receiver.disconnect(); }
});

test('preview refreshes installed voices and keeps speech available if no match exists', async () => {
  const voices = [], options = [];
  const receiver = createReceiver({
    status() {},
    speech: {stop: async () => false, getAvailableVoicesAsync: async () => voices,
      speak: (text, value) => options.push(value)},
  });
  for (const [name, id] of [['Flo','flo'], ['Lee','lee'], ['Eddy','eddy'], ['Reed','reed']]) {
    voices.push({name, identifier:id, language:'en-AU'});
    receiver.testVoice();
    await flush();
  }
  assert.deepEqual(options.map(value => value.voice), [undefined, 'lee', 'eddy', 'reed']);
  assert.ok(options.every(value => value.rate === 1.5));
});

test('a stop during voice lookup retires old speech', async () => {
  let resolveVoices;
  const spoken = [];
  const receiver = createReceiver({
    status() {},
    speech: {stop: async () => false,
      getAvailableVoicesAsync: () => new Promise(resolve => { resolveVoices = resolve; }),
      speak: text => spoken.push(text)},
  });
  receiver.testVoice();
  receiver.stop();
  resolveVoices([]);
  await flush();
  assert.deepEqual(spoken, []);
});

test('queued sound starts before its phrase and immediate sound can play during speech', async () => {
  const events = [];
  const player = {
    isLoaded: true, currentTime: 0.4,
    seekTo: () => new Promise(resolve => { player.rewound = resolve; }),
    play: () => events.push('cue'), pause: () => events.push('pause'),
  };
  const socket = {readyState: 1, close() {}, send() {}};
  const receiver = createReceiver({
    status() {}, cuePlayer: player, openSocket: () => socket,
    speech: {stop: async () => false, speak: text => events.push(text)},
  });
  const send = record => socket.onmessage({data: JSON.stringify(record)});
  try {
    receiver.connect();
    send({type: 'ready', id: 0});
    send({type: 'cue', name: 'open-object'});
    send({type: 'speak', text: 'Compose prompt'});
    await flush();
    assert.deepEqual(events, []);
    player.rewound();
    await flush();
    assert.deepEqual(events, ['cue', 'Compose prompt']);
    player.currentTime = 0;
    send({type: 'cue', name: 'open-object', immediate: true});
    send({type: 'stop', scope: 'speech'});
    assert.deepEqual(events, ['cue', 'Compose prompt', 'pause', 'cue']);
    receiver.stop();
    assert.equal(events.at(-1), 'pause');
  } finally { receiver.disconnect(); }
});

test('Stop during rewind and reconnection discard stale cues and allow the next cue', async () => {
  let rewind, plays = 0;
  const player = {
    isLoaded: true, currentTime: 0.4,
    seekTo: () => new Promise(resolve => { rewind = resolve; }),
    play: () => { plays++; }, pause() {},
  };
  const sockets = [];
  const spoken = [];
  const receiver = createReceiver({
    status() {}, cuePlayer: player,
    openSocket() {
      const socket = {readyState: 1, close() {}, send() {}};
      sockets.push(socket);
      return socket;
    },
    speech: {stop: async () => false, speak: text => spoken.push(text)},
  });
  const send = (record, socket = sockets.at(-1)) => socket.onmessage({data: JSON.stringify(record)});
  const cue = {type: 'cue', name: 'open-object'};
  try {
    receiver.connect();
    send({type: 'ready', id: 0});
    send(cue);
    send({type: 'speak', text: 'old'});
    await flush();
    receiver.stop();
    send({...cue, immediate: true});
    receiver.disconnect();
    receiver.connect();
    send({type: 'ready', id: 0});
    send({...cue, immediate: true}, sockets[0]);
    rewind();
    await flush();
    assert.equal(plays, 0);
    assert.deepEqual(spoken, []);
    player.currentTime = 0;
    send(cue);
    send({type: 'speak', text: 'new'});
    await flush();
    assert.equal(plays, 1);
    assert.deepEqual(spoken, ['new']);
  } finally { receiver.disconnect(); }
});
