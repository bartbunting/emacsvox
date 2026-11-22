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
