// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later

import React, {useEffect, useMemo, useRef, useState} from 'react';
import {AppState, ScrollView, StatusBar, StyleSheet, Text, View} from 'react-native';
import {registerRootComponent, requireNativeView, requireOptionalNativeModule} from 'expo';
import {Asset} from 'expo-asset';
import {useAudioPlayer} from 'expo-audio';
import * as Speech from 'expo-speech';
import {WebView} from '@expo/dom-webview';
import {keyboardSource} from './keyboard';
import {mixerAdapters} from './mixer';
import {createReceiver} from './receiver';
import {Action, colors, Panel, Settings} from './panels';

const native = requireOptionalNativeModule('IphoneMixer');
const ssh = requireOptionalNativeModule('IphoneTerminal');
const Terminal = ssh ? requireNativeView('IphoneTerminal') : null;
const sound = require('./assets/open-object.wav');
const relayPort = process.env.EXPO_PUBLIC_EMACSVOX_PORT || '8787';

function connectionKey(p) {
  return JSON.stringify([p.transport, p.audio, p.host, p.port, p.username, p.pin]);
}

function validHost(host) {
  const parts = host.split('.');
  return parts.length === 4 && parts.every(n => /^\d{1,3}$/.test(n) && Number(n) <= 255) &&
    Number(parts[0]) === 100 && Number(parts[1]) >= 64 && Number(parts[1]) <= 127;
}

async function prepareAudio() {
  const asset = await Asset.fromModule(sound).downloadAsync();
  await native.prepare(asset.localUri);
}

function App() {
  const [settings, setSettings] = useState(() => ({
    host: process.env.EXPO_PUBLIC_EMACSVOX_HOST ?? '', port: '8822', username: '', pin: '',
    transport: ssh ? 'ssh' : 'relay', input: 'field', keepAwake: 'yes', audio: 'direct',
    ...ssh?.loadProfile(),
  }));
  const active = useRef(false);
  const reconnect = useRef(false);
  function save(draft) {
    const next = Object.fromEntries(Object.entries(draft).map(([key, value]) => [key, value.trim()]));
    ssh?.saveProfile(next);
    reconnect.current = connectionKey(settings) !== connectionKey(next) && active.current;
    setSettings(next);
  }
  return <Session key={connectionKey(settings)} settings={settings} save={save} active={active} reconnect={reconnect} />;
}

function Session({settings, save, active, reconnect}) {
  const [panel, setPanel] = useState(null);
  const [draft, setDraft] = useState(settings);
  const [status, setStatus] = useState('Disconnected');
  const [activeSession, setActiveSession] = useState(false);
  const [playback, setPlayback] = useState('');
  const [offer, setOffer] = useState(null);
  const terminalRef = useRef(null);
  const [voice, setVoice] = useState('');
  const [keyboard, setKeyboard] = useState(null);
  const [screen, setScreen] = useState('');
  const [timing, setTiming] = useState('');
  const sshMode = Boolean(ssh) && settings.transport === 'ssh';
  const mixed = Boolean(native) && settings.audio === 'mixed';
  const directCue = useAudioPlayer(sound, {downloadFirst: true});
  const adapters = useMemo(() => mixed ? mixerAdapters(native, Speech, setTiming)
    : {speech: Speech, cuePlayer: directCue}, [mixed, directCue]);
  const [prepared, setPrepared] = useState(!mixed);
  const [prepareAttempt, setPrepareAttempt] = useState(0);
  const [audioFailed, setAudioFailed] = useState(false);
  const host = settings.host;
  const receiver = useMemo(() => createReceiver({
    ...adapters,
    notificationPlayer: native?.permission && {
      speak: (text, voice, rate) => native.permission(text, voice, rate),
      stop: () => native.stopPermission(),
    },
    tonePlayer: native?.queueTone && {
      prepare: prepareAudio, play: (hz, ms) => native.queueTone(hz, ms), stop: () => native.stopEffects(),
    },
    status: setStatus, playback: setPlayback, voiceStatus: setVoice, keyboard: setKeyboard,
    screen: setScreen, sshOffer: setOffer,
    sessionActive: value => { active.current = value; setActiveSession(value); },
    openSocket: () => new WebSocket('ws://' + host + (sshMode ? ':8797/speech/ssh' : ':' + relayPort + '/speech')),
  }), [adapters, host, sshMode, active]);
  useEffect(() => {
    if (!mixed) return;
    let live = true;
    prepareAudio().then(() => { if (live) setPrepared(true); }, () => {
      if (live) { setAudioFailed(true); setStatus('Could not prepare the native mixer.'); }
    });
    return () => { live = false; };
  }, [mixed, prepareAttempt]);
  useEffect(() => {
    const listener = AppState.addEventListener('change', receiver.appState);
    receiver.appState(AppState.currentState);
    return () => { listener.remove(); receiver.disconnect(); };
  }, [receiver]);
  useEffect(() => {
    if (reconnect.current && prepared) { reconnect.current = false; connect(); }
  }, [receiver, prepared]);
  useEffect(() => {
    if (!ssh) return;
    ssh.keepAwake(settings.keepAwake === 'yes' && activeSession);
    return () => { ssh.keepAwake(false); };
  }, [activeSession, settings.keepAwake]);
  function openSettings() { setDraft(settings); setPanel('settings'); }
  function connect() {
    if (!validHost(host) || (sshMode && (!/^\d{1,5}$/.test(settings.port) ||
        Number(settings.port) < 1 || Number(settings.port) > 65535 || !settings.username ||
        !/^ssh-ed25519 [A-Za-z0-9+/=]+(?: .*)?$/.test(settings.pin)))) {
      setStatus('Enter the WSL connection details in Settings, then save.');
      if (ssh) openSettings();
      return;
    }
    if (audioFailed) {
      setAudioFailed(false);
      reconnect.current = true;
      setPrepareAttempt(n => n + 1);
    } else if (prepared) receiver.connect();
  }
  const useField = sshMode && offer && settings.input === 'field';
  return <>
    <StatusBar barStyle="light-content" />
    <ScrollView style={styles.surface} contentContainerStyle={styles.page} accessibilityElementsHidden={Boolean(panel)}
      contentInsetAdjustmentBehavior="automatic" keyboardShouldPersistTaps="handled">
      <Text accessibilityRole="header" style={styles.heading}>Emacsvox Speech</Text>
      <Text accessibilityLabel={'Connection status. ' + status} style={styles.status}>{status}</Text>
      <View style={styles.actions}>
        {activeSession ? <Action title="Disconnect" onPress={() => receiver.disconnect()} />
          : <Action title="Connect" disabled={!prepared && !audioFailed} onPress={connect} />}
        <Action title="Stop Speech" onPress={receiver.stop} />
      </View>
      {sshMode && offer && !useField &&
        <Action title="Focus Emacs terminal" onPress={() => terminalRef.current?.focusKeyboard()} />}
      {(useField || keyboard) && <View key={'keyboard-' + (offer?.frame ?? 'relay')} style={styles.keyboard}>
        <WebView source={keyboardSource} style={styles.surface} scrollEnabled={false}
          onMessage={({nativeEvent}) => {
            if (useField) terminalRef.current?.sendKeys(offer.frame, nativeEvent.data);
            else keyboard?.sendKeys(nativeEvent.data);
          }}
          onContentProcessDidTerminate={() => receiver.disconnect('Keyboard closed. Activate Connect to retry.')} />
      </View>}
      {sshMode && offer && <Terminal key={offer.frame} ref={terminalRef} style={styles.nativeTerminal}
        connection={{host, port:settings.port, username:settings.username, pin:settings.pin, ...offer}}
        onSessionStatus={({nativeEvent}) => {
          if (nativeEvent.state !== 'connected') receiver.terminalClosed(nativeEvent.frame, nativeEvent.detail);
        }} />}
      {screen ? <View><Text accessibilityRole="header" style={styles.status}>Terminal screen</Text>
        <Text selectable style={styles.terminal}>{screen}</Text></View> : null}
      <View style={styles.actions}>
        {(ssh || native) && <Action title="Settings" onPress={openSettings} />}
        <Action title="Diagnostics" onPress={() => setPanel('diagnostics')} />
      </View>
    </ScrollView>
    {panel === 'settings' && <Settings draft={draft} ssh={ssh} mixer={native}
      edit={(k,v) => setDraft(prev => ({...prev, [k]:v}))}
      cancel={() => setPanel(null)} save={() => { save(draft); setPanel(null); }} />}
    {panel === 'diagnostics' && <Panel title="Diagnostics" close={() => setPanel(null)}>
      <Action title="Done" onPress={() => setPanel(null)} />
      {voice ? <Text style={styles.status}>{voice}</Text> : null}
      {native && <Text style={styles.status}>{mixed ? 'Native mixer' : 'Direct speech'}</Text>}
      <Action title="Test iPhone Voice" disabled={!prepared} onPress={receiver.testVoice} />
      {native && <Action title="Test half-second tone" onPress={() => receiver.testTone(480)} />}
      {native && <Action title="Test three-second tone" onPress={() => receiver.testTone(3000)} />}
      <Action title="Test Open Object Sound" disabled={!prepared} onPress={receiver.testCue} />
      {mixed && <Action title="Test mixed audio" disabled={!prepared} onPress={receiver.testMix} />}
      <Action title="Stop Speech" onPress={receiver.stop} />
      {timing ? <Text style={styles.status}>{timing}</Text> : null}
      {playback ? <Text style={styles.status}>{playback}</Text> : null}
    </Panel>}
  </>;
}

const styles = StyleSheet.create({
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
