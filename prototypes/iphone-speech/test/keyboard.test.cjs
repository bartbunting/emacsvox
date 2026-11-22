// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later

const test = require('node:test');
const assert = require('node:assert/strict');
const { keyboardField } = require('./keyboard-field.cjs');
const { createReceiver } = require('../receiver');

test('keyboard field forwards Emacs sequences and committed Unicode text', () => {
  const sent = [];
  const {field, listeners, down} = keyboardField(text => sent.push(text));
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

test('Option letters send Meta once and leave VoiceOver chords to iOS', () => {
  const sent = [];
  const {down} = keyboardField(text => sent.push(text));
  assert.ok(down('x', {altKey: true}));
  assert.ok(down('≈', {altKey: true, code: 'KeyX'}));
  assert.ok(down('ƒ', {altKey: true, code: 'KeyF'}));
  assert.ok(down('Dead', {altKey: true, shiftKey: true, code: 'KeyE'}));
  assert.ok(down('a', {altKey: true, code: 'KeyQ'}));
  assert.ok(!down('ƒ', {altKey: true, ctrlKey: true, code: 'KeyF'}));
  assert.ok(!down('ƒ', {altKey: true, metaKey: true, code: 'KeyF'}));
  assert.ok(!down('Dead', {altKey: true, isComposing: true, code: 'KeyE'}));
  assert.ok(!down('Alt', {altKey: true, code: 'AltLeft'}));
  assert.deepEqual(sent, ['\x1bx', '\x1bx', '\x1bf', '\x1bE', '\x1ba']);
});

test('old keyboard events cannot enter a replacement session', () => {
  const sent = [];
  let field, socket;
  const receiver = createReceiver({
    speech: {stop: async () => true}, status() {}, keyboard: value => { field = value; },
    openSocket: () => (socket = {readyState: 1, send: text => sent.push(text), close() {}}),
  });
  const ready = (keyboard, id = 0) => socket.onmessage({data: JSON.stringify({type:'ready', id, keyboard})});
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
    receiver.stop();
    ready(true, 1);
    old.sendKeys('stale');
    field.sendKeys('b');
    assert.deepEqual(sent, ['key a', 'reset 1', 'key b']);
  } finally { receiver.disconnect(); }
});
