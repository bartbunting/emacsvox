// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later

const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const { keyboardSource } = require('../keyboard');
const { createReceiver } = require('../receiver');

test('keyboard field forwards Emacs sequences and committed Unicode text', () => {
  const listeners = {}, sent = [];
  const field = {value: '', addEventListener(name, fn) { listeners[name] = fn; }};
  const html = decodeURIComponent(keyboardSource.uri.split(',')[1]);
  vm.runInNewContext(html.match(/<script>([\s\S]*?)<\/script>/)[1], {
    document: {getElementById: () => field},
    window: {ReactNativeWebView: {postMessage: text => sent.push(text)}},
  });
  function down(key, modifiers) {
    let prevented = false;
    listeners.keydown({key, ...modifiers, preventDefault() { prevented = true; }});
    return prevented;
  }
  for (const key of ['n', 'x', 'f', 's', 'g']) assert.ok(down(key, {ctrlKey: true}));
  assert.ok(down('Escape'));
  assert.ok(!down('x'));
  field.value = 'x';
  listeners.input({});
  assert.ok(!down('n', {ctrlKey: true, altKey: true}));
  assert.ok(!down('c', {metaKey: true}));
  assert.deepEqual(sent, ['\x0e', '\x18', '\x06', '\x13', '\x07', '\x1b', 'x']);
  sent.length = 0;
  field.value = 'é'.repeat(255) + '🌱';
  listeners.input({isComposing: true});
  assert.equal(sent.length, 0);
  listeners.compositionend();
  listeners.input({});
  assert.deepEqual(sent, ['é'.repeat(255), '🌱']);
  assert.equal(field.value, '');
});

test('old keyboard events cannot enter a replacement session', () => {
  const sent = [];
  let field, socket;
  const receiver = createReceiver({
    speech: {stop: async () => true}, status() {}, keyboard: value => { field = value; },
    openSocket: () => (socket = {readyState: 1, send: text => sent.push(text), close() {}}),
  });
  const ready = keyboard => socket.onmessage({data: JSON.stringify({type:'ready', id:0, keyboard})});
  try {
    receiver.connect();
    ready(true);
    const old = field;
    old.sendKeys('a');
    receiver.connect();
    ready(false);
    assert.equal(field, null);
    old.sendKeys('stale');
    receiver.connect();
    ready(true);
    old.sendKeys('stale');
    field.sendKeys('b');
    assert.deepEqual(sent, ['key a', 'key b']);
  } finally { receiver.disconnect(); }
});
