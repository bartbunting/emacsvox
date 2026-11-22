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
