// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later

// Run with the app's matching react-test-renderer on NODE_PATH.
const test = require('node:test');
const assert = require('node:assert/strict');
const {createRequire} = require('node:module');
const path = require('node:path');
const {transformFileSync} = require('@babel/core');
const {create, act} = require('react-test-renderer');
const React = createRequire(require.resolve('react-test-renderer'))('react');

// Load the production components and receiver. Only the phone and network
// boundaries are stand-ins, so tab presses use React's real reconciliation.
function loadComponent(filename, platform) {
  const file = path.resolve(__dirname, '..', filename);
  const localRequire = createRequire(file);
  const {code} = transformFileSync(file, {babelrc: false, configFile: false,
    plugins: ['@babel/plugin-transform-react-jsx', '@babel/plugin-transform-modules-commonjs']});
  const exports = {};
  Function('require', 'exports', code)(name => Object.hasOwn(platform, name)
    ? platform[name] : localRequire(name), exports);
  return exports;
}

for (const input of ['field', 'terminal']) {
  test('switch tabs with a connected ' + input + ' keyboard', async t => {
    const sockets = [], focus = [];
    t.mock.method(global, 'WebSocket', function openSocket() {
      const socket = {readyState: 1, close() { this.readyState = 3; }};
      sockets.push(socket);
      return socket;
    });
    global.IS_REACT_ACT_ENVIRONMENT = true;
    global.requestAnimationFrame = setImmediate;
    global.cancelAnimationFrame = clearImmediate;
    const profile = {host: '100.64.0.1', port: '8822', username: 'test', pin: 'ssh-ed25519 AA==', input};
    const ssh = {loadProfile: () => profile, keepAwake() {}, saveProfile(next) { Object.assign(profile, next); }};
    const player = {};
    const rn = Object.fromEntries(['Button', 'View', 'Text', 'ScrollView', 'SafeAreaView', 'Pressable',
      'KeyboardAvoidingView', 'Switch', 'TextInput', 'StatusBar', 'Modal'].map(name => [name, name]));
    rn.StyleSheet = {create: value => value, absoluteFill: {position: 'absolute'}};
    rn.AppState = {currentState: 'active', addEventListener: () => ({remove() {}})};
    rn.AccessibilityInfo = {sendAccessibilityEvent() {}};
    let App;
    const platform = {react: React, 'react-native': rn,
      expo: {registerRootComponent: root => { App = root; }, requireNativeView: () => 'NativeTerminal',
        requireOptionalNativeModule: name => name === 'IphoneTerminal' ? ssh : null},
      'expo-asset': {}, 'expo-speech': {stop: async () => {}, getAvailableVoicesAsync: async () => []},
      'expo-audio': {useAudioPlayer: () => player}, '@expo/dom-webview': {WebView: 'WebView'},
      './assets/open-object.wav': 1, './assets/visual-line.wav': 2};
    platform['./panels'] = loadComponent('panels.js', platform);
    loadComponent('index.js', platform);
    let app;
    await act(() => {
      app = create(React.createElement(App), {createNodeMock: ({type}) => ({
        focusKeyboard: () => focus.push(type), injectJavaScript: () => focus.push(type),
      })});
    });
    t.after(() => act(() => app.unmount()));
    const tabs = () => app.root.findAllByType('Pressable');
    const select = name => act(() => tabs().find(el => el.props.accessibilityLabel === name).props.onPress());
    const button = title => app.root.findAllByType('Button').find(el => el.props.title === title);
    const hostField = () => app.root.findAllByType('TextInput').find(el => el.props.accessibilityLabel === 'WSL Tailscale IPv4 address');
    assert.deepEqual(tabs().map(el => [el.props.accessibilityLabel, el.props.accessibilityRole,
      el.props.accessibilityState.selected]), [['Terminal','tab',true], ['Diagnostics','tab',false], ['Settings','tab',false]]);
    await act(() => button('Connect').props.onPress());
    assert.equal(sockets.length, 1);
    const ws = sockets[0];
    const receive = record => ws.onmessage({data: JSON.stringify(record)});
    await act(() => receive({type:'ssh', frame:'same-frame', client:'client', server:'server'}));
    const terminal = app.root.findByType('NativeTerminal');
    await select('Settings');
    assert.equal(terminal.props.keyboardEnabled, false);
    assert.ok(app.root.findAllByType('ScrollView').some(el => el.props.accessibilityElementsHidden));
    await act(() => hostField().props.onChangeText('100.64.0.2'));
    await act(() => {
      terminal.props.onSessionStatus({nativeEvent: {state: 'connected'}});
      receive({type: 'ready', id: 0});
    });
    await select('Diagnostics');
    assert.ok(tabs()[1].props.accessibilityState.selected);
    assert.ok(button('Test iPhone Voice'));
    assert.equal(app.root.findAllByType('WebView').length, 0);
    await select('Settings');
    assert.equal(hostField().props.value, '100.64.0.2');
    assert.deepEqual(focus, []);
    await act(() => button('Cancel').props.onPress());
    assert.equal(app.root.findByType('NativeTerminal'), terminal);
    assert.equal(terminal.props.keyboardEnabled, true);
    if (input === 'field') {
      await act(() => app.root.findByType('WebView').props.onMessage({nativeEvent: {data: ''}}));
    }
    assert.deepEqual(focus, [input === 'field' ? 'WebView' : 'NativeTerminal']);
    await select('Settings');
    assert.equal(hostField().props.value, '100.64.0.1');
    const keepAwake = app.root.findAllByType('Switch').find(el => el.props.accessibilityLabel === 'Keep awake while connected');
    await act(() => keepAwake.props.onValueChange(false));
    await act(() => button('Save settings').props.onPress());
    assert.equal(profile.keepAwake, 'no');
    assert.ok(tabs()[0].props.accessibilityState.selected);
    assert.equal(app.root.findByType('NativeTerminal'), terminal);
    assert.equal(sockets.length, 1);
    assert.equal(ws.readyState, 1);
  });
}
