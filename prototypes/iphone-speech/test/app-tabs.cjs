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
const {keyboardField} = require('./keyboard-field.cjs');

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

for (const [input, hasShiftReturnShortcut] of [['field', true], ['terminal', true], ['field', false]]) {
  test('switch tabs with a connected ' + input + ' keyboard' + (hasShiftReturnShortcut ? '' : ' on an earlier app'), async t => {
    const sockets = [], focus = [], keys = [];
    t.mock.method(global, 'WebSocket', function openSocket(url) {
      const socket = {url, readyState: 1, send() {}, close() { this.readyState = 3; }};
      sockets.push(socket);
      return socket;
    });
    global.IS_REACT_ACT_ENVIRONMENT = true;
    global.requestAnimationFrame = setImmediate;
    global.cancelAnimationFrame = clearImmediate;
    const vpnHost = hasShiftReturnShortcut ? (input === 'field' ? '10.8.0.1' : '172.20.0.1') : '100.64.0.1';
    const profile = {host: input === 'terminal' ? '203.0.113.1' : vpnHost,
      port: '8822', username: 'test', pin: 'ssh-ed25519 AA==', input};
    const logging = [], trace = {setSpeechLogging: on => logging.push(on), speechTrace: () => 'local speech sample'};
    const levels = [], listeners = {}, records = [], announcements = [];
    let clock = 50, trial;
    if (hasShiftReturnShortcut) {
      profile.worker = 'omnivox';
      profile.speechLoudness = '2';
      Object.assign(trace, {hasAudioRoutePicker: true, setSpeechLoudness: async db => levels.push(db), timingClock: () => clock,
        armKeyTiming: async (connection, serial) => { trial = {connection, serial}; },
        open: async () => {}, close: async () => {}, record: async (_, lane, line) => { records.push([lane, line]); },
        addListener: (name, cb) => { listeners[name] = cb; return {remove() { delete listeners[name]; }}; }});
    }
    let savedHistory = ['Earlier. Could not reach the Emacs host on SSH port 8822.'];
    const ssh = {hasShiftReturnShortcut, hasModifiedLetterShortcuts: hasShiftReturnShortcut, hasWebBrowser: hasShiftReturnShortcut, loadProfile: () => profile,
      loadConnectionHistory: () => savedHistory, saveConnectionHistory(entries) { savedHistory = entries; },
      keepAwake() {}, saveProfile(next) { Object.assign(profile, next); }};
    const links = [];
    let dismiss;
    const player = {};
    const rn = Object.fromEntries(['Button', 'View', 'Text', 'ScrollView', 'SafeAreaView', 'Pressable',
      'KeyboardAvoidingView', 'Switch', 'TextInput', 'StatusBar', 'Modal'].map(name => [name, name]));
    rn.StyleSheet = {create: value => value, absoluteFill: {position: 'absolute'}};
    rn.AppState = {currentState: 'active', addEventListener: () => ({remove() {}})};
    rn.AccessibilityInfo = {sendAccessibilityEvent() {}, announceForAccessibility(text) { announcements.push(text); }};
    let App;
    const platform = {react: React, 'react-native': rn,
      expo: {registerRootComponent: root => { App = root; }, requireNativeView: (_, name) => name ?? 'NativeTerminal',
        requireOptionalNativeModule: name => name === 'IphoneTerminal' ? ssh : name === 'IphoneOmnivox' ? trace : null},
      'expo-asset': {}, 'expo-speech': {stop: async () => {}, getAvailableVoicesAsync: async () => []},
      'expo-audio': {useAudioPlayer: () => player}, '@expo/dom-webview': {WebView: 'WebView'},
      './assets/open-object.wav': 1, './assets/visual-line.wav': 2};
    platform['./panels'] = loadComponent('panels.js', platform);
    loadComponent('index.js', platform);
    let app;
    await act(() => {
      app = create(React.createElement(App), {createNodeMock: ({type}) => ({
        focusKeyboard: () => focus.push(type), injectJavaScript: () => focus.push(type),
        sendKeys: (frame, bytes) => keys.push([frame, bytes]),
        openWebLink: (...args) => { links.push(args); return new Promise(done => { dismiss = done; }); },
      })});
    });
    t.after(() => act(() => app.unmount()));
    const presses = () => app.root.findAllByType('Pressable');
    const tabs = () => presses().filter(el => el.props.accessibilityRole === 'tab');
    const select = name => act(() => presses().find(el => el.props.accessibilityLabel === name).props.onPress());
    const button = title => app.root.findAllByType('Button').find(el => el.props.title === title);
    const hostField = () => app.root.findAllByType('TextInput').find(el => el.props.accessibilityLabel === 'Emacs host VPN IPv4 address');
    assert.deepEqual(tabs().map(el => [el.props.accessibilityLabel, el.props.accessibilityRole,
      el.props.accessibilityState.selected]), [['Terminal','tab',true], ['Diagnostics','tab',false], ['Settings','tab',false]]);
    if (input === 'terminal') {
      await act(() => button('Connect').props.onPress());
      assert.equal(sockets.length, 0);
      assert.ok(tabs()[2].props.accessibilityState.selected);
      await select('Connection');
      await act(() => hostField().props.onChangeText(vpnHost));
      await act(() => button('Save settings').props.onPress());
    }
    await act(() => button('Connect').props.onPress());
    assert.equal(sockets.length, 1);
    const ws = sockets[0];
    assert.equal(new URL(ws.url).hostname, vpnHost);
    const receive = record => ws.onmessage({data: JSON.stringify(record)});
    await act(() => receive({type:'ssh', frame:'same-frame', client:'client', server:'server',
      host:'unused.test', port:'1', username:'unused', pin:'unused'}));
    const terminal = app.root.findByType('NativeTerminal');
    assert.deepEqual(terminal.props.connection, {host:profile.host, port:profile.port,
      username:profile.username, pin:profile.pin, frame:'same-frame', client:'client', server:'server'});
    await select('Settings');
    assert.equal(app.root.findAllByType('PhoneAudioRouteView').length, 0);
    assert.equal(terminal.props.keyboardEnabled, false);
    assert.ok(app.root.findAllByType('ScrollView').some(el => el.props.accessibilityElementsHidden));
    assert.equal(hostField(), undefined);
    await select('Connection');
    await act(() => hostField().props.onChangeText('100.64.0.2'));
    await act(() => {
      terminal.props.onSessionStatus({nativeEvent: {state: 'connected'}});
      receive({type: 'ready', id: 0});
    });
    await select('Diagnostics');
    assert.ok(tabs()[1].props.accessibilityState.selected);
    assert.match(savedHistory[0], /SSH terminal opened\./);
    assert.equal(savedHistory.length, 2);
    assert.equal(app.root.findAll(el => el.type === 'Text' && el.props.children === savedHistory[1]).length, 0);
    await select('Connection history');
    assert.equal(app.root.findAll(el => el.type === 'Text' && el.props.children === savedHistory[1]).length, 1);
    assert.ok(button('Test iPhone Voice'));
    assert.equal(button('Test Open Object Sound'), undefined);
    await select('Audio tests');
    assert.ok(button('Test Open Object Sound'));
    await select('Audio tests');
    assert.equal(button('Read speech trace'), undefined);
    assert.deepEqual(logging, [false]);
    assert.equal(app.root.findAllByType('WebView').length, 0);
    assert.equal(app.root.findAllByType('PhoneKeyboardContainer').length, 0);
    await select('Settings');
    await select('Connection');
    assert.equal(hostField().props.value, '100.64.0.2');
    if (hasShiftReturnShortcut) {
      await select('Speech and sounds');
      assert.equal(hostField(), undefined);
      const slider = app.root.findByType('PhoneSpeechLoudnessView');
      assert.equal(slider.props.level, 2);
      await act(() => slider.props.onLevelChange({nativeEvent: {decibels: 6}}));
      assert.deepEqual(levels, [2]);
    }
    assert.deepEqual(focus, []);
    await act(() => button('Cancel').props.onPress());
    assert.equal(app.root.findByType('NativeTerminal'), terminal);
    assert.equal(terminal.props.keyboardEnabled, true);
    if (input === 'field') {
      await act(() => app.root.findByType('WebView').props.onMessage({nativeEvent: {data: ''}}));
      if (hasShiftReturnShortcut) {
        const container = app.root.findByType('PhoneKeyboardContainer');
        assert.ok(container.props.active);
        await act(() => container.props.onShiftReturn());
      } else {
        assert.equal(app.root.findAllByType('PhoneKeyboardContainer').length, 0);
        await act(() => app.root.findByType('WebView').props.onMessage({nativeEvent: {data: '\x1b[27;2;13~'}}));
      }
      assert.deepEqual(keys, [['same-frame', '\x1b[27;2;13~']]);
    }
    assert.deepEqual(focus, [input === 'field' ? 'WebView' : 'NativeTerminal']);
    await select('Settings');
    await select('Connection');
    assert.equal(hostField().props.value, vpnHost);
    await select('Speech and sounds');
    assert.equal(app.root.findAllByType('PhoneAudioRouteView').length, hasShiftReturnShortcut ? 1 : 0);
    const loggingSwitch = () => app.root.findAllByType('Switch').find(el => el.props.accessibilityLabel === 'Log speech text and timing');
    if (hasShiftReturnShortcut) {
      const slider = app.root.findByType('PhoneSpeechLoudnessView');
      assert.equal(slider.props.level, 2);
      await act(() => slider.props.onLevelChange({nativeEvent: {decibels: 3}}));
    }
    await act(() => loggingSwitch().props.onValueChange(true));
    assert.equal(terminal.props.minimumColumns, 120);
    await select('Keyboard and terminal');
    const keepAwake = app.root.findAllByType('Switch').find(el => el.props.accessibilityLabel === 'Keep awake while connected');
    const columns = app.root.findAllByType('TextInput').find(el => el.props.accessibilityLabel === 'Minimum terminal columns');
    await act(() => columns.props.onChangeText('160'));
    await act(() => keepAwake.props.onValueChange(false));
    await act(() => button('Save settings').props.onPress());
    assert.equal(profile.keepAwake, 'no');
    assert.equal(terminal.props.minimumColumns, 160);
    assert.equal(profile.terminalColumns, '160');
    if (hasShiftReturnShortcut) {
      assert.equal(profile.speechLoudness, '3');
      assert.deepEqual(levels, [2, 3]);
    }
    assert.ok(tabs()[0].props.accessibilityState.selected);
    assert.equal(app.root.findByType('NativeTerminal'), terminal);
    assert.equal(sockets.length, 1);
    assert.equal(ws.readyState, 1);
    assert.deepEqual(logging, [false, true]);
    await select('Diagnostics');
    await select('Speech trace');
    await act(() => button('Read speech trace').props.onPress());
    assert.ok(app.root.findAllByType('Text').some(el => el.props.children === 'local speech sample'));
    assert.ok(button('Send speech trace to Emacs host'));
    await select('Settings');
    await select('Speech and sounds');
    await act(() => loggingSwitch().props.onValueChange(false));
    await act(() => button('Save settings').props.onPress());
    await select('Diagnostics');
    assert.equal(button('Read speech trace'), undefined);
    assert.deepEqual(logging, [false, true, false]);
    if (hasShiftReturnShortcut) {
      await select('Timing tests');
      const shows = text => app.root.findAllByType('Text').some(el => el.props.children === text);
      assert.ok(shows('No timing measurements yet.'));
      await act(() => button('Measure SSH key to speech').props.onPress());
      assert.ok(tabs()[1].props.accessibilityState.selected);
      assert.ok(app.root.findAllByType('Text').some(el => el.props.children === 'The connected Emacs frame does not offer the timing test.'));
      await act(() => receive({type: 'ready', id: 0, keyTiming: true}));
      await act(() => button('Measure SSH key to speech').props.onPress());
      assert.ok(tabs()[1].props.accessibilityState.selected);
      assert.equal(terminal.props.keyboardEnabled, false);
      const field = keyboardField(data => app.root.findByType('WebView').props.onMessage({nativeEvent: {data}}));
      // WebKit can deliver Return as an inserted newline instead of a keydown.
      await act(() => { field.field.value = '\n'; field.listeners.input({isComposing: false}); });
      assert.deepEqual(keys.at(-1), ['same-frame', '\x1b[57343;1u']);
      clock = 60;
      await act(() => {
        ws.onmessage({data: 'M q {timing sample 1 }'});
        listeners.keyTiming({...trial, event: 'buffer', time: 85, route: 'Bluetooth', outputLatencyMs: 42});
      });
      assert.ok(tabs()[1].props.accessibilityState.selected);
      const sshResult = 'SSH. Key to returned speech 10 milliseconds. Key to first scheduled audio 35 milliseconds. Bluetooth output. iOS reports 42 milliseconds of output latency.';
      assert.ok(shows(sshResult));
      assert.equal(announcements.at(-1), sshResult);
      await act(() => button('Measure local key to speech').props.onPress());
      await act(() => { button('Start timing with this button').props.onPress(); });
      await act(() => listeners.keyTiming({...trial, event: 'buffer', time: 92}));
      const localResult = 'Local speech. Button to first scheduled audio 32 milliseconds.';
      assert.ok(shows(localResult));
      assert.ok(shows(sshResult));
      assert.equal(announcements.at(-1), localResult);
      await act(() => button('Read timing results aloud').props.onPress());
      assert.deepEqual(records.at(-1), ['M', 'tts_say ' + sshResult + ' ' + localResult]);
      await act(() => button('Measure local key to speech').props.onPress());
      await act(() => { field.down('Escape', {}); });
      assert.ok(tabs()[1].props.accessibilityState.selected);
      assert.ok(shows('Timing cancelled.'));
      t.mock.timers.enable({apis: ['setTimeout']});
      await act(() => button('Measure SSH key to speech').props.onPress());
      await act(() => { t.mock.timers.tick(60000); });
      assert.ok(shows('The test did not receive Return or a button press. Choose a measurement to try again.'));
      assert.ok(shows(sshResult));
      assert.ok(shows(localResult));
      assert.equal(app.root.findAllByType('WebView').length, 0);
      t.mock.timers.reset();
      await act(() => button('Measure local key to speech').props.onPress());
      await select('Terminal');
      await select('Diagnostics');
      assert.ok(shows('Timing cancelled.'));
      assert.ok(shows(sshResult));
      assert.ok(shows(localResult));
      assert.equal(app.root.findAllByType('WebView').length, 0);
      await act(() => button('Measure local key to speech').props.onPress());
      await act(() => { field.down('Enter', {code: 'Enter'}); });
      await act(() => listeners.keyTiming({...trial, event: 'speech', time: 87}));
      assert.ok(shows('Local speech. Key to speech start callback 27 milliseconds.'));
      assert.deepEqual(keys.at(-1), ['same-frame', '\x1b[57343;1u']);
      await select('Terminal');
      const link = 'https://example.org/a%20b#c';
      await act(() => {
        receive({type: 'ready', id: 0, keyTiming: true, browseUrl: true});
        receive({type: 'open-url', frame: 'same-frame', url: link});
      });
      assert.deepEqual(links, [['same-frame', link, false]]);
      assert.equal(terminal.props.keyboardEnabled, false);
      await act(() => dismiss(true));
      assert.equal(terminal.props.keyboardEnabled, true);
      assert.equal(app.root.findByType('NativeTerminal'), terminal);
      if (input === 'field') {
        const old = app.root.findByType('WebView');
        await act(() => old.props.onContentProcessDidTerminate());
        const fresh = app.root.findByType('WebView');
        assert.notEqual(fresh, old);
        await act(() => fresh.props.onMessage({nativeEvent: {data: ''}}));
        await act(() => app.root.findByType('PhoneKeyboardContainer').props.onModifiedKey({nativeEvent: {text: '\x1b:'}}));
        assert.deepEqual(keys.at(-1), ['same-frame', '\x1b:']);
        assert.equal(app.root.findByType('NativeTerminal'), terminal);
        assert.equal(sockets.length, 1);
      }
      await select('Settings');
      await select('Keyboard and terminal');
      const browse = app.root.findAllByType('Switch').find(el => el.props.accessibilityLabel === 'Open web links inside Emacsvox Speech');
      await act(() => browse.props.onValueChange(false));
      await act(() => button('Save settings').props.onPress());
      await act(() => receive({type: 'open-url', frame: 'same-frame', url: link}));
      assert.deepEqual(links.at(-1), ['same-frame', link, true]);
      await act(() => dismiss(true));
      assert.equal(sockets.length, 1);
    }
  });
}
