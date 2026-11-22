// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later

const {test} = require('node:test');
const assert = require('node:assert/strict');
const {createReceiver} = require('../receiver');
const {mixerAdapters} = require('../mixer');
const flush = () => new Promise(resolve => setImmediate(resolve));

test('a stopped mixed preview cannot finish a replacement line or publish its timing', async () => {
  const calls = [], stops = [], timing = [], playback = [];
  const native = {
    stop: async all => { stops.push(all); },
    speak: (...args) => new Promise(resolve => calls.push({args, resolve})),
  };
  const socket = {readyState: 1, close() {}, send() {}};
  const direct = {getAvailableVoicesAsync: async () => [{name:'Reed', language:'en-US', identifier:'reed'}]};
  const receiver = createReceiver({...mixerAdapters(native, direct, text => timing.push(text)),
    status() {}, playback: state => playback.push(state), openSocket: () => socket});
  const send = record => socket.onmessage({data:JSON.stringify(record)});
  try {
    receiver.connect();
    send({type:'ready', id:0});
    receiver.testMix();
    await flush();
    assert.deepEqual(calls[0].args.slice(1), ['reed', 1.5, true]);
    send({type:'stop', scope:'speech'});
    send({type:'speak', text:'New line'});
    await flush();
    calls[0].resolve({state:'done', firstBufferMs:900});
    await flush();
    assert.deepEqual(timing, []);
    assert.deepEqual(calls[1].args, ['New line', 'reed', 1.5, false]);
    calls[1].resolve({state:'done', firstBufferMs:37});
    await flush();
    assert.deepEqual(timing, ['First speech buffer after 37 milliseconds.']);
    assert.equal(playback.at(-1), 'iOS finished speech.');
    assert.equal(stops.at(-1), false);
    receiver.stop();
    assert.equal(stops.at(-1), true);
  } finally { receiver.disconnect(); }
});
