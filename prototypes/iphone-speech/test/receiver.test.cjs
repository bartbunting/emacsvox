// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later

const test = require('node:test');
const assert = require('node:assert/strict');
const { createReceiver } = require('../receiver');
const flush = () => new Promise(resolve => setImmediate(resolve));

test('speech text is sent only on request to a relay that advertises trace storage', async () => {
  const sent = [], messages = [];
  const ws = {readyState: 1, send: text => sent.push(text), close() {}};
  const nativeWire = {open: async () => {}, close: async () => {}, stopPermission: async () => {},
    addListener: () => ({remove() {}}), speechTrace: () => 'Lime Plum'};
  const receiver = createReceiver({openSocket: () => ws, nativeWire, status() {}, playback: text => messages.push(text),
    speech: {stop: async () => true}});
  try {
    receiver.connect();
    const deliver = record => ws.onmessage({data: JSON.stringify(record)});
    deliver({type: 'ssh', frame: 'phone', server: 'server', client: 'client'});
    deliver({type: 'ready', id: 0});
    receiver.sendSpeechTrace();
    assert.match(messages.at(-1), /needs an update/);
    deliver({type: 'ready', id: 0, speechTrace: true});
    assert.deepEqual(sent, []);
    receiver.sendSpeechTrace();
    receiver.sendSpeechTrace();
    assert.deepEqual(sent, ['speech-trace Lime Plum']);
    deliver({type: 'trace-saved', ok: true});
    assert.equal(messages.at(-1), 'Speech trace saved in WSL.');
  } finally { receiver.disconnect(); }
});

test('unlock reattaches once with fresh speech and ignores the replaced SSH view', async () => {
  const sockets = [], spoken = [];
  const receiver = createReceiver({
    openSocket() { const ws = {close() {}}; sockets.push(ws); return ws; },
    status() {}, speech: {stop: async () => true, speak: text => spoken.push(text)},
  });
  const send = (ws, data) => ws.onmessage({data:JSON.stringify(data)});
  try {
    receiver.connect();
    const old = sockets[0];
    send(old, {type:'ssh', frame:'first', server:'server', client:'client'});
    send(old, {type:'ready', id:0});
    send(old, {type:'speak', text:'obsolete'});
    receiver.appState('inactive');
    receiver.appState('active');
    assert.equal(sockets.length, 1);
    receiver.appState('inactive');
    old.onclose();
    receiver.appState('background');
    receiver.appState('background');
    receiver.appState('active');
    receiver.appState('active');
    assert.equal(sockets.length, 2);
    const fresh = sockets[1];
    send(fresh, {type:'ssh', frame:'second', server:'server', client:'client'});
    receiver.terminalClosed('first', 'Late close from background');
    old.onclose();
    send(old, {type:'speak', text:'late'});
    send(fresh, {type:'ready', id:0});
    send(fresh, {type:'speak', text:'new line'});
    await flush();
    assert.deepEqual(spoken, ['new line']);
    receiver.disconnect();
    receiver.appState('background');
    receiver.appState('active');
    assert.equal(sockets.length, 2);
  } finally { receiver.disconnect(); }
});

test('unlock retries a waking network and Disconnect or a rejected host stops retries', t => {
  t.mock.timers.enable({apis:['setTimeout']});
  const sockets = [];
  const receiver = createReceiver({
    openSocket() { const ws = {close() {}}; sockets.push(ws); return ws; },
    status() {}, speech: {stop: async () => true},
  });
  function unlock() { receiver.appState('background'); receiver.appState('active'); }
  try {
    receiver.connect();
    unlock();
    sockets.at(-1).onclose();
    t.mock.timers.tick(1000);
    assert.equal(sockets.length, 3);
    const ws = sockets.at(-1);
    ws.onmessage({data:JSON.stringify({type:'ssh', frame:'second', server:'s', client:'c'})});
    receiver.terminalClosed('second', 'The SSH host key does not match.');
    t.mock.timers.tick(10000);
    assert.equal(sockets.length, 3);
    receiver.connect();
    unlock();
    sockets.at(-1).onerror();
    receiver.disconnect();
    t.mock.timers.tick(20000);
    assert.equal(sockets.length, 5);
  } finally { receiver.disconnect(); }
});

test('the diagnostic tones use the local cancellable Emacs tone player without a connection', async () => {
  const played = [];
  let stops = 0;
  const receiver = createReceiver({
    openSocket: () => assert.fail('Local tone opened a connection'), status() {},
    speech: {stop: async () => true}, tonePlayer: {prepare: async () => {},
      play: (hz, ms) => played.push([hz, ms]), stop: () => { stops++; }},
  });
  receiver.testTone(480);
  await flush();
  receiver.testTone(3000);
  await flush();
  receiver.stop();
  assert.deepEqual(played, [[660,480], [660,3000]]);
  assert.equal(stops, 3);
});

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

test('visual-line chime replaces its spoken label when ready and Stop cancels a pending rewind', async () => {
  const events = [];
  let rewound;
  const player = {isLoaded: false, currentTime: 0,
    seekTo: () => new Promise(resolve => { rewound = resolve; }),
    play: () => events.push('chime'), pause: () => events.push('pause')};
  const socket = {close() {}, send() {}, readyState: 1};
  const receiver = createReceiver({status() {}, openSocket: () => socket, visualLinePlayer: player,
    speech: {stop: async () => true, speak: (text, options) => { events.push(text); options.onDone(); }}});
  const send = packet => socket.onmessage({data: JSON.stringify(packet)});
  const cue = {type:'speak', text:'Visual lines', cue:'visual-line'};
  try {
    receiver.connect();
    send({type:'ready', id:0});
    send({...cue, immediate:true});
    await flush();
    player.isLoaded = true;
    send(cue);
    send({type:'speak', text:'Org'});
    await flush();
    assert.deepEqual(events, ['Visual lines', 'chime', 'Org']);
    player.currentTime = 0.4;
    send({...cue, immediate:true});
    receiver.stop();
    rewound();
    await flush();
    assert.deepEqual(events, ['Visual lines', 'chime', 'Org', 'pause']);
  } finally { receiver.disconnect(); }
});

test('rapid navigation preserves active and pending permission identities until Stop', async () => {
  const spoken = [], stops = [];
  const socket = {readyState: 1, send() {}, close() {}};
  const receiver = createReceiver({status() {}, openSocket: () => socket,
    speech: {stop: async () => { stops.push(true); }, speak: (text, cb) => spoken.push([text, cb])}});
  const send = record => socket.onmessage({data: JSON.stringify(record)});
  try {
    receiver.connect();
    send({type: 'ready', id: 0});
    send({type: 'permission', id: '1', text: 'First request'});
    send({type: 'stop'});
    send({type: 'speak', text: 'old line'});
    send({type: 'permission', id: '2', text: 'Second request'});
    send({type: 'permission', id: '2', text: 'Duplicate'});
    await flush();
    const before = stops.length;
    send({type: 'stop'});
    send({type: 'speak', text: 'latest line'});
    assert.equal(stops.length, before);
    assert.deepEqual(spoken.map(p => p[0]), ['First request']);
    spoken[0][1].onDone();
    await flush();
    spoken[1][1].onDone();
    await flush();
    assert.deepEqual(spoken.map(p => p[0]), ['First request', 'Second request', 'latest line']);
    send({type: 'permission', id: '3', text: 'Pending request'});
    send({type: 'stop', scope: 'all'});
    await flush();
    assert.equal(spoken.length, 3);
  } finally { receiver.disconnect(); }
});

test('native notification has its own speaker, while tone preparation and rate follow navigation', async () => {
  const socket = {readyState: 1, send() {}, close() {}};
  const spoken = [], urgent = [], tones = [];
  let releaseTone, releasePermission, permissionStops = 0;
  const receiver = createReceiver({status() {}, openSocket: () => socket,
    speech: {stop: async () => {}, speak: (text, opts) => spoken.push([text, opts.rate])},
    tonePlayer: {prepare: () => new Promise(done => { releaseTone = done; }), play: hz => tones.push(hz), stop() {}},
    notificationPlayer: {speak: text => new Promise(done => { urgent.push(text); releasePermission = done; }),
      stop() { permissionStops++; releasePermission?.(); }}});
  const send = packet => socket.onmessage({data: JSON.stringify(packet)});
  try {
    receiver.connect();
    send({type: 'ready', id: 0});
    send({type: 'permission', id: 'one', text: 'Inspect sample'});
    send({type: 'tone', hz: 440, ms: 30});
    await flush();
    const before = permissionStops;
    send({type: 'stop'});
    send({type: 'letter', text: 'Z', rate: 1.35});
    releaseTone();
    await flush();
    assert.deepEqual(tones, []);
    assert.deepEqual(spoken, [['capital Z', 1.35]]);
    assert.deepEqual(urgent, ['Inspect sample']);
    assert.equal(permissionStops, before);
    receiver.stop();
    assert.equal(permissionStops, before + 1);
  } finally { receiver.disconnect(); }
});
