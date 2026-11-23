// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later

import React, {useEffect, useMemo, useRef, useState} from 'react';
import {AppState, KeyboardAvoidingView, SafeAreaView, ScrollView, StatusBar, StyleSheet, Text, View} from 'react-native';
import {registerRootComponent, requireNativeView, requireOptionalNativeModule} from 'expo';
import {Asset} from 'expo-asset';
import {useAudioPlayer} from 'expo-audio';
import * as Speech from 'expo-speech';
import {WebView} from '@expo/dom-webview';
import {keyboardSource, createKeyboardFocus} from './keyboard';
import {mixerAdapters} from './mixer';
import {createReceiver} from './receiver';
import {Action, colors, Settings, TabBar, TabPage, TerminalReview} from './panels';

const native = requireOptionalNativeModule('IphoneMixer');
const ssh = requireOptionalNativeModule('IphoneTerminal');
const Terminal = ssh ? requireNativeView('IphoneTerminal') : null;
const KeyboardContainer = ssh?.hasShiftReturnShortcut ? requireNativeView('IphoneTerminal', 'PhoneKeyboardContainer') : View;
const sound = require('./assets/open-object.wav');
const chime = require('./assets/visual-line.wav');
const relayPort = process.env.EXPO_PUBLIC_EMACSVOX_PORT || '8787';

const nativeWire = requireOptionalNativeModule('IphoneOmnivox');

function connectionKey(p) {
  return JSON.stringify([p.transport, p.audio, p.worker, p.host, p.port, p.username, p.pin]);
}

function validHost(host) {
  const parts = host.split('.');
  return parts.length === 4 && parts.every(n => /^\d{1,3}$/.test(n) && Number(n) <= 255) &&
    Number(parts[0]) === 100 && Number(parts[1]) >= 64 && Number(parts[1]) <= 127;
}

let audioPreparation;
let nativeChimeReady = false;
function prepareAudio() {
  if (!audioPreparation) {
    audioPreparation = Asset.fromModule(sound).downloadAsync()
      .then(asset => native.prepare(asset.localUri))
      .catch(error => { audioPreparation = undefined; throw error; });
  }
  return audioPreparation;
}

function App() {
  const [settings, setSettings] = useState(() => ({
    host: process.env.EXPO_PUBLIC_EMACSVOX_HOST ?? '', port: '8822', username: '', pin: '',
    transport: ssh ? 'ssh' : 'relay', input: 'field', keepAwake: 'yes', audio: 'direct',
    connectOnOpen: 'no', controlOption: 'voiceover',
    ...ssh?.loadProfile(),
  }));
  const active = useRef(false);
  const reconnect = useRef(Boolean(ssh && settings.transport === 'ssh' && settings.connectOnOpen === 'yes'));
  function save(draft) {
    const next = Object.fromEntries(Object.entries(draft).map(([key, value]) => [key, value.trim()]));
    ssh?.saveProfile(next);
    reconnect.current = connectionKey(settings) !== connectionKey(next) && active.current;
    setSettings(next);
  }
  return <Session key={connectionKey(settings)} settings={settings} save={save} active={active} reconnect={reconnect} />;
}

function EmacsKeyboard({canFocus, controlOption, onKeys, onClosed}) {
  const view = useRef(null);
  const [focusNewInput] = useState(createKeyboardFocus);
  const [loaded, setLoaded] = useState(false);
  useEffect(() => {
    focusNewInput(loaded && view.current, canFocus,
      input => input.injectJavaScript("document.getElementById('keys').focus();"));
  }, [loaded, canFocus, focusNewInput]);
  const shortcuts = ssh?.hasShiftReturnShortcut ? {
    active: canFocus,
    onShiftReturn: () => { if (canFocus) onKeys('\x1b[27;2;13~'); },
  } : {};
  return <KeyboardContainer style={styles.keyboard} {...shortcuts}>
    <WebView ref={view} source={keyboardSource} style={styles.surface} scrollEnabled={false}
      injectedJavaScriptBeforeContentLoaded={controlOption ? 'window.emacsControlOption = true;' : undefined}
      injectedJavaScript="window.ReactNativeWebView.postMessage('');"
      onMessage={({nativeEvent}) => {
        // The document sends an empty message at load. Key packets are nonempty.
        if (nativeEvent.data === '') setLoaded(true);
        else if (canFocus) onKeys(nativeEvent.data);
      }}
      onContentProcessDidTerminate={onClosed} />
  </KeyboardContainer>;
}

function Session({settings, save, active, reconnect}) {
  const [tab, setTab] = useState('Terminal');
  const [reviewOpen, setReviewOpen] = useState(false);
  const terminalTab = tab === 'Terminal';
  const [draft, setDraft] = useState(settings);
  const [status, setStatus] = useState('Disconnected');
  const [activeSession, setActiveSession] = useState(false);
  const [playback, setPlayback] = useState('');
  const [offer, setOffer] = useState(null);
  const terminalRef = useRef(null);
  const [focusNewTerminal] = useState(createKeyboardFocus);
  const [foreground, setForeground] = useState(AppState.currentState === 'active');
  const [voice, setVoice] = useState('');
  const [keyboard, setKeyboard] = useState(null);
  const [screen, setScreen] = useState('');
  const [timing, setTiming] = useState('');
  const sshMode = Boolean(ssh) && settings.transport === 'ssh';
  const useWire = sshMode && Boolean(nativeWire) && settings.worker === 'omnivox';
  const mixed = !useWire && Boolean(native) && settings.audio === 'mixed';
  const directCue = useAudioPlayer(sound, {downloadFirst: true});
  const directChime = useAudioPlayer(chime, {downloadFirst: true});
  const adapters = useMemo(() => mixed ? mixerAdapters(native, Speech, setTiming, () => nativeChimeReady)
    : {speech: Speech, cuePlayer: directCue, visualLinePlayer: directChime}, [mixed, directCue, directChime]);
  const [prepared, setPrepared] = useState(!mixed);
  const [prepareAttempt, setPrepareAttempt] = useState(0);
  const [audioFailed, setAudioFailed] = useState(false);
  const host = settings.host;
  const receiver = useMemo(() => createReceiver({
    ...adapters, nativeWire: useWire ? nativeWire : null,
    notificationPlayer: native?.permission && {
      speak: (text, voice, rate) => native.permission(text, voice, rate),
      stop: () => native.stopPermission(),
    },
    tonePlayer: native?.queueTone && {
      prepare: prepareAudio, play: (hz, ms) => native.queueTone(hz, ms), stop: () => native.stopEffects(),
    },
    status: setStatus, playback: setPlayback, voiceStatus: setVoice, keyboard: setKeyboard,
    screen: setScreen, sshOffer: value => {
      setOffer(value);
      if (!value) setReviewOpen(false);
    },
    sessionActive: value => { active.current = value; setActiveSession(value); },
    openSocket: () => new WebSocket('ws://' + host + (sshMode ? (useWire ? ':8797/speech/ssh/omnivox' : ':8797/speech/ssh') : ':' + relayPort + '/speech')),
  }), [adapters, host, sshMode, useWire, active]);
  useEffect(() => {
    if (!mixed) return;
    let live = true;
    prepareAudio().then(async () => {
      if (!live) return;
      setPrepared(true);
      if (native.prepareChime && !nativeChimeReady) {
        try {
          const asset = await Asset.fromModule(chime).downloadAsync();
          await native.prepareChime(asset.localUri);
          nativeChimeReady = true;
        } catch {
          if (live) setPlayback('Visual-line chime unavailable. Emacs will say Visual lines.');
        }
      }
    }, () => {
      if (live) { setAudioFailed(true); setStatus('Could not prepare the native mixer.'); }
    });
    return () => { live = false; };
  }, [mixed, prepareAttempt]);
  useEffect(() => {
    function onState(state) {
      setForeground(state === 'active');
      receiver.appState(state);
    }
    const listener = AppState.addEventListener('change', onState);
    onState(AppState.currentState);
    return () => { listener.remove(); receiver.disconnect(); };
  }, [receiver]);
  useEffect(() => {
    if (reconnect.current && prepared && foreground && terminalTab && !reviewOpen) {
      reconnect.current = false;
      connect();
    }
  }, [receiver, prepared, foreground, terminalTab, reviewOpen]);
  useEffect(() => {
    if (!ssh) return;
    ssh.keepAwake(settings.keepAwake === 'yes' && activeSession);
    return () => { ssh.keepAwake(false); };
  }, [activeSession, settings.keepAwake]);
  function connect() {
    if (!validHost(host) || (sshMode && (!/^\d{1,5}$/.test(settings.port) ||
        Number(settings.port) < 1 || Number(settings.port) > 65535 || !settings.username ||
        !/^ssh-ed25519 [A-Za-z0-9+/=]+(?: .*)?$/.test(settings.pin)))) {
      setStatus('Enter the WSL connection details in Settings, then save.');
      setTab('Settings');
      return;
    }
    if (audioFailed) {
      setAudioFailed(false);
      reconnect.current = true;
      setPrepareAttempt(n => n + 1);
    } else if (prepared) {
      if (native && !mixed) void prepareAudio().catch(() => {});
      receiver.connect();
    }
  }
  const useField = sshMode && offer && settings.input === 'field';
  const keyboardFrame = sshMode && offer && keyboard?.frame === offer.frame ? offer.frame : null;
  const canFocus = foreground && terminalTab && !reviewOpen;
  useEffect(() => {
    focusNewTerminal(terminalTab && !useField && keyboardFrame, canFocus && terminalRef.current,
      () => terminalRef.current.focusKeyboard());
  }, [useField, keyboardFrame, terminalTab, canFocus, focusNewTerminal]);
  // SwiftTerm closes SSH if its view is detached. Keep it behind the active tab.
  const terminalPage = (
    <ScrollView style={styles.surface} contentContainerStyle={styles.page} keyboardShouldPersistTaps="handled"
      pointerEvents={terminalTab ? 'auto' : 'none'} accessibilityElementsHidden={!terminalTab || reviewOpen}
      importantForAccessibility={terminalTab && !reviewOpen ? 'auto' : 'no-hide-descendants'}>
      <Text accessibilityRole="header" style={styles.heading}>Terminal</Text>
      <Text accessibilityLabel={'Connection status. ' + status} style={styles.status}>{status}</Text>
      <View style={styles.actions}>
        {activeSession ? <Action title="Disconnect" onPress={() => receiver.disconnect()} />
          : <Action title="Connect" disabled={!prepared && !audioFailed} onPress={connect} />}
        <Action title="Stop Speech" onPress={receiver.stop} />
      </View>
      {sshMode && offer && !useField &&
        <Action title="Focus Emacs terminal" onPress={() => terminalRef.current?.focusKeyboard()} />}
      {terminalTab && ((useField && keyboardFrame) || keyboard?.sendKeys) &&
        <EmacsKeyboard key={'keyboard-' + (keyboardFrame ?? 'relay') + settings.controlOption} canFocus={canFocus}
          controlOption={settings.controlOption === 'emacs'}
          onKeys={text => {
            if (useField) terminalRef.current?.sendKeys(keyboardFrame, text);
            else keyboard?.sendKeys(text);
          }}
          onClosed={() => {
            const message = 'Keyboard closed. Activate Connect to retry.';
            if (keyboardFrame) receiver.terminalClosed(keyboardFrame, message);
            else receiver.disconnect(message);
          }} />}
      {sshMode && offer && <View key={offer.frame} collapsable={false} accessibilityElementsHidden={Boolean(useField)}>
        <Terminal ref={terminalRef} style={styles.nativeTerminal}
          keyboardEnabled={canFocus}
          connection={{host, port:settings.port, username:settings.username, pin:settings.pin, ...offer}}
          onSessionStatus={({nativeEvent}) => {
            if (nativeEvent.state === 'connected') receiver.terminalConnected(offer.frame);
            else receiver.terminalClosed(nativeEvent.frame, nativeEvent.detail);
          }} /></View>}
      {screen ? <View><Text accessibilityRole="header" style={styles.status}>Terminal screen</Text>
        <Text selectable style={styles.terminal}>{screen}</Text></View> : null}
      {sshMode && offer && <Action title="Review terminal screen" onPress={() => setReviewOpen(true)} />}
    </ScrollView>
  );
  const diagnostics = (
    <TabPage title="Diagnostics">
      {voice ? <Text style={styles.status}>{voice}</Text> : null}
      {native && <Text style={styles.status}>{useWire ? 'Omnivox on iPhone' : mixed ? 'Native mixer' : 'Direct speech'}</Text>}
      <Action title="Test iPhone Voice" disabled={!prepared} onPress={receiver.testVoice} />
      {useWire && <Action title="Test timing inside TestCase" disabled={!activeSession} onPress={receiver.testMarkers} />}
      {native && <Action title="Test half-second tone" onPress={() => receiver.testTone(480)} />}
      {native && <Action title="Test three-second tone" onPress={() => receiver.testTone(3000)} />}
      <Action title="Test Open Object Sound" disabled={!prepared} onPress={receiver.testCue} />
      {adapters.visualLinePlayer && <Action title="Test visual-line chime" disabled={!prepared} onPress={receiver.testVisualLine} />}
      {mixed && <Action title="Test mixed audio" disabled={!prepared} onPress={receiver.testMix} />}
      <Action title="Stop Speech" onPress={receiver.stop} />
      {timing ? <Text style={styles.status}>{timing}</Text> : null}
      {playback ? <Text style={styles.status}>{playback}</Text> : null}
    </TabPage>
  );
  return <KeyboardAvoidingView behavior="padding" style={styles.root}>
    <StatusBar barStyle="light-content" />
    <SafeAreaView style={styles.root}>
      <View style={styles.content}>
        {terminalPage}
        {!terminalTab && <View style={styles.tabPage}>
          {tab === 'Diagnostics' ? diagnostics : <Settings draft={draft} ssh={ssh} mixer={native} wire={nativeWire}
            edit={(k,v) => setDraft(prev => ({...prev, [k]:v}))}
            cancel={() => { setDraft(settings); setTab('Terminal'); }}
            save={() => { save(draft); setTab('Terminal'); }} />}
        </View>}
      </View>
      <TabBar selected={tab} onSelect={setTab} />
    </SafeAreaView>
    {reviewOpen && offer && <TerminalReview key={offer.frame} terminalRef={terminalRef} frame={offer.frame}
      close={() => setReviewOpen(false)} />}
  </KeyboardAvoidingView>;
}

const styles = StyleSheet.create({
  root: {flex: 1, backgroundColor: colors.background},
  content: {flex: 1},
  tabPage: {...StyleSheet.absoluteFill, backgroundColor: colors.background},
  surface: {backgroundColor: colors.background},
  page: {flexGrow: 1, gap: 16, backgroundColor: colors.background, paddingHorizontal: 20, paddingVertical: 36},
  heading: {fontSize: 28, fontWeight: '600', color: colors.text},
  status: {fontSize: 20, color: colors.text},
  actions: {flexDirection: 'row', flexWrap: 'wrap', alignItems: 'center', gap: 12},
  nativeTerminal: {height: 360, backgroundColor: colors.background},
  keyboard: {height: 100, alignSelf: 'stretch'},
  terminal: {fontFamily: 'Menlo', fontSize: 14, color: colors.text},
});

registerRootComponent(App);
