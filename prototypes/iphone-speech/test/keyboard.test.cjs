// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later

const test = require('node:test');
const assert = require('node:assert/strict');
const { keyboardField } = require('./keyboard-field.cjs');
const { createKeyboardFocus } = require('../keyboard');
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

test('hardware j and Shift+j bypass text editing, while composition and paste use the field', () => {
  const sent = [];
  const {field, listeners, down} = keyboardField(text => sent.push(text));
  assert.ok(down('j', {code: 'KeyJ'}));
  assert.ok(down('J', {code: 'KeyJ', shiftKey: true}));
  assert.ok(down('a', {code: 'KeyQ'}));
  assert.ok(!down('j', {code: 'KeyJ', isComposing: true}));
  assert.ok(!down('j', {code: 'KeyJ', keyCode: 229}));
  assert.ok(!down('j', {code: 'KeyJ', cancelable: false}));
  assert.ok(!down('j', {code: 'KeyJ', getModifierState: key => key === 'AltGraph'}));
  assert.ok(!down('Process', {code: 'KeyJ'}));
  assert.ok(!down('j'));
  assert.ok(!down('j', {code: 'Unidentified'}));
  field.value = '日本';
  listeners.compositionend();
  listeners.input({});
  field.value = 'pasted';
  listeners.input({});
  assert.deepEqual(sent, ['j', 'J', 'a', '日本', 'pasted']);
});

test('Option punctuation sends one Emacs Meta chord and ordinary accents remain text', () => {
  const sent = [];
  const {field, listeners, down} = keyboardField(text => sent.push(text));
  const meta = {altKey: true, shiftKey: true};
  assert.ok(down('˘', {...meta, code: 'Period'}));
  assert.ok(down('¯', {...meta, code: 'Comma'}));
  assert.ok(down('Dead', {...meta, code: 'Period'}));
  assert.ok(down('˘', {...meta, code: 'Unidentified'}));
  assert.ok(down('¯', {...meta, getModifierState: key => key === 'AltGraph'}));
  assert.ok(down('<', {altKey: true, code: 'IntlBackslash'}));
  assert.ok(down('>', {...meta, code: 'IntlBackslash'}));
  assert.ok(!down('˘', {...meta, ctrlKey: true, code: 'Period'}));
  assert.ok(!down('¯', {...meta, metaKey: true, code: 'Comma'}));
  assert.ok(!down('Dead', {...meta, isComposing: true, code: 'Comma'}));
  assert.ok(down('>', {shiftKey: true, code: 'Period'}));
  field.value = '¯˘';
  listeners.input({});
  assert.deepEqual(sent, ['\x1b>', '\x1b<', '\x1b>', '\x1b>', '\x1b<', '\x1b<', '\x1b>', '>', '¯˘']);
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

test('terminal modifiers, function keys and Control+Meta with either VoiceOver modifier', () => {
  const bytes = [];
  const field = keyboardField(key => bytes.push(key));
  const meta = {altKey: true};
  const ctrl = {ctrlKey: true};
  const both = {...ctrl, ...meta};
  for (const [key, modifiers, expected] of [
    [' ', ctrl, '\x00'], ['6', ctrl, '\x1e'], ['_', ctrl, '\x1f'], ['/', ctrl, '\x1b[27;5;47~'],
    ['ﬁ', {...meta, code: 'Digit5', shiftKey: true}, '\x1b%'],
    ['…', {...meta, code: 'Semicolon'}, '\x1b;'], ['Dead', {...meta, code: 'KeyU'}, '\x1bu'],
    ['Backspace', meta, '\x1b\x7f'], ['ArrowRight', ctrl, '\x1b[1;5C'],
    ['ArrowLeft', meta, '\x1b[1;3D'], ['PageDown', {shiftKey: true}, '\x1b[6;2~'],
    ['Tab', {shiftKey: true}, '\x1b[Z'], ['Tab', ctrl, '\x1b[27;5;9~'],
    ['Enter', {code: 'Enter', shiftKey: true}, '\x1b[27;2;13~'],
    ['Unidentified', {code: 'Enter', shiftKey: true}, '\x1b[27;2;13~'],
    ['Return', {code: 'NumpadEnter', shiftKey: true}, '\x1b[27;2;13~'],
    ['Enter', {code: 'Enter', getModifierState: key => key === 'Shift'}, '\x1b[27;2;13~'],
    ['Enter', {code: 'Enter'}, '\r'],
    ['j', {...ctrl, code: 'KeyJ'}, '\n'], ['\n', {...ctrl, code: 'KeyJ'}, '\n'],
    ['F1', {}, '\x1bOP'], ['F4', ctrl, '\x1b[1;5S'], ['F12', {}, '\x1b[24~'],
  ]) {
    assert.ok(field.down(key, modifiers), key);
    assert.equal(bytes.pop(), expected, key);
  }
  assert.ok(!field.down('f', both));
  assert.ok(field.down('Escape'));
  assert.ok(field.down('f', ctrl));
  assert.equal(bytes.join(''), '\x1b\x06');
  bytes.length = 0;
  const unlocked = keyboardField(key => bytes.push(key), true);
  assert.ok(unlocked.down('ƒ', {...both, code: 'KeyF'}));
  assert.ok(unlocked.down('ArrowLeft', both));
  assert.ok(!unlocked.down('f', {...both, metaKey: true}));
  assert.ok(!unlocked.down('@', {...both, getModifierState: key => key === 'AltGraph'}));
  assert.deepEqual(bytes, ['\x1b\x06', '\x1b[1;7D']);
});

test('SSH keyboard becomes available once both the terminal and speech frame are ready', () => {
  const events = [];
  let socket;
  const receiver = createReceiver({
    speech: {stop: async () => true}, status() {}, keyboard: value => events.push(value?.frame ?? null),
    openSocket: () => (socket = {readyState: 1, close() {}, send() {}}),
  });
  const packet = value => socket.onmessage({data: JSON.stringify(value)});
  const offer = frame => packet({type:'ssh', frame, client:'client', server:'server'});
  const ready = (id = 0) => packet({type:'ready', id});
  try {
    receiver.connect();
    offer('first');
    ready();
    assert.deepEqual(events, [null]);
    receiver.terminalConnected('first');
    receiver.stop();
    ready(1);
    assert.deepEqual(events, [null, 'first']);
    receiver.disconnect();
    receiver.connect();
    offer('second');
    receiver.terminalConnected('first');
    receiver.terminalConnected('second');
    assert.equal(events.at(-1), null);
    ready();
    assert.equal(events.at(-1), 'second');
    receiver.disconnect();
    receiver.terminalConnected('second');
    assert.equal(events.at(-1), null);
  } finally { receiver.disconnect(); }
});

test('keyboard focus waits for a visible ready input and stays put after Stop or Settings', () => {
  const focus = createKeyboardFocus(), requests = [];
  const request = target => requests.push(target);
  focus(null, true, request);
  focus('first', false, request);
  assert.deepEqual(requests, []);
  focus('first', true, request);
  focus('first', true, request);
  focus('first', false, request);
  focus('first', true, request);
  assert.deepEqual(requests, ['first']);
  focus(null, false, request);
  focus('second', false, request);
  focus('second', true, request);
  assert.deepEqual(requests, ['first', 'second']);
});
