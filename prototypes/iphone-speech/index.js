// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later

import React, { useEffect, useMemo, useRef, useState } from 'react';
import { AppState, Button, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { registerRootComponent, requireNativeView, requireOptionalNativeModule } from 'expo';
import { Asset } from 'expo-asset';
import { mixerAdapters } from './mixer';
import { useAudioPlayer } from 'expo-audio';
import * as Speech from 'expo-speech';
import { createReceiver } from './receiver';
import { WebView } from '@expo/dom-webview';
import { keyboardSource } from './keyboard';

const native = requireOptionalNativeModule('IphoneMixer');
const ssh = requireOptionalNativeModule('IphoneTerminal');
const Terminal = ssh ? requireNativeView('IphoneTerminal') : null;
const sound = require('./assets/open-object.wav');

function App() {
  const [mixed, setMixed] = useState(false);
  return <Session key={String(mixed)} mixed={mixed} switchMode={() => setMixed(value => !value)} />;
}

function Session({mixed, switchMode}) {
  const [status, setStatus] = useState('Disconnected');
  const [playback, setPlayback] = useState('');
  const [sshMode, setSshMode] = useState(Boolean(ssh));
  const [fields, setFields] = useState(() => ({host: process.env.EXPO_PUBLIC_EMACSVOX_HOST ?? '',
    port: '8822', username: '', pin: '', ...ssh?.loadProfile()}));
  const [profile, setProfile] = useState(null);
  const [offer, setOffer] = useState(null);
  const terminalRef = useRef(null);
  const [voice, setVoice] = useState('');
  const [keyboard, setKeyboard] = useState(null);
  const [screen, setScreen] = useState('');
  const directCue = useAudioPlayer(sound, {downloadFirst: true});
  const [timing, setTiming] = useState('');
  const [loading, setLoading] = useState(false);
  const adapters = useMemo(() => mixed
    ? mixerAdapters(native, Speech, setTiming)
    : {speech: Speech, cuePlayer: directCue}, [mixed, directCue]);
  const receiver = useMemo(() => createReceiver({
    ...adapters,
    status: setStatus,
    playback: setPlayback,
    voiceStatus: setVoice,
    keyboard: setKeyboard,
    screen: setScreen,
    sshOffer: setOffer,
    openSocket: () => sshMode
      ? new WebSocket('ws://' + profile.host + ':8797/speech/ssh')
      : new WebSocket('ws://' + process.env.EXPO_PUBLIC_EMACSVOX_HOST + ':' +
          (process.env.EXPO_PUBLIC_EMACSVOX_PORT || '8787') + '/speech'),
  }), [adapters, sshMode, profile]);
  const begin = useRef(false);
  useEffect(() => {
    if (begin.current && profile) { begin.current = false; receiver.connect(); }
  }, [receiver, profile]);
  function connect() {
    if (!sshMode) return receiver.connect();
    const next = Object.fromEntries(Object.entries(fields).map(([k, v]) => [k, v.trim()]));
    const octets = next.host.split('.');
    if (octets.length !== 4 || octets.some(n => !/^\d{1,3}$/.test(n) || Number(n) > 255) ||
        Number(octets[0]) !== 100 || Number(octets[1]) < 64 || Number(octets[1]) > 127 ||
        !/^\d{1,5}$/.test(next.port) || Number(next.port) < 1 || Number(next.port) > 65535 ||
        !next.username || !/^ssh-ed25519 [A-Za-z0-9+/=]+(?: .*)?$/.test(next.pin)) {
      setStatus('Enter the WSL Tailscale address, SSH port, username and full Ed25519 host public key.');
      return;
    }
    ssh.saveProfile(next);
    begin.current = true;
    setProfile(next);
  }
  useEffect(() => {
    const listener = AppState.addEventListener('change', state => {
      if (state === 'background') receiver.disconnect();
    });
    return () => { listener.remove(); receiver.disconnect(); };
  }, [receiver]);
  async function changeMode() {
    if (!mixed) {
      setLoading(true);
      try {
        const asset = await Asset.fromModule(sound).downloadAsync();
        await native.prepare(asset.localUri);
      } catch {
        setPlayback('Could not load the local Accent recording for the mixer.');
        setLoading(false);
        return;
      }
    }
    switchMode();
  }
  return (
    <ScrollView contentInsetAdjustmentBehavior="automatic" contentContainerStyle={styles.page}>
      <Text accessibilityRole="header" style={styles.heading}>Emacsvox Speech</Text>
      <Text accessibilityLabel={'Connection status. ' + status} style={styles.status}>{status}</Text>
      {voice ? <Text style={styles.status}>{voice}</Text> : null}
      {native && <Text style={styles.status}>{mixed ? 'Native mixer' : 'Direct speech'}</Text>}
      <View style={styles.controls}>
        {ssh && <Button title={sshMode ? 'Use relay keyboard' : 'Use SSH terminal'}
          onPress={() => { receiver.disconnect(); setSshMode(value => !value); }} />}
        {sshMode && <View style={styles.profile}>
          {[['host','WSL Tailscale IPv4 address'], ['port','SSH port'], ['username','WSL username'],
            ['pin','Trusted WSL host public key']].map(([name,label]) => <View key={name}>
            <Text>{label}</Text>
            <TextInput accessibilityLabel={label} autoCapitalize="none" autoCorrect={false}
              style={styles.field} value={fields[name]} onChangeText={v => setFields(f => ({...f,[name]:v}))} />
          </View>)}
          <Button title="Copy iPhone SSH public key" onPress={async () => {
            try { await ssh.copyPublicKey(); setStatus('iPhone public key copied.'); }
            catch { setStatus('Could not read the iPhone SSH identity.'); }
          }} />
        </View>}
        <Button title="Connect" accessibilityLabel="Connect" onPress={connect} />
        <Button title="Disconnect" accessibilityLabel="Disconnect" onPress={() => receiver.disconnect()} />
        <Button title="Stop Speech" accessibilityLabel="Stop Speech" onPress={receiver.stop} />
        {sshMode && offer && profile && <View style={styles.profile}>
          <Button title="Focus Emacs terminal" onPress={() => terminalRef.current?.focusKeyboard()} />
          <Terminal ref={terminalRef} style={styles.nativeTerminal} connection={{...profile, ...offer}}
            onSessionStatus={({nativeEvent}) => {
              if (nativeEvent.state !== 'connected') receiver.disconnect(nativeEvent.detail || 'SSH terminal closed.');
            }} />
        </View>}
        {keyboard && <View style={styles.keyboard}>
          <WebView source={keyboardSource} scrollEnabled={false}
            onMessage={event => keyboard.sendKeys(event.nativeEvent.data)}
            onContentProcessDidTerminate={() => receiver.disconnect('Keyboard closed. Activate Connect to retry.')} />
        </View>}
        <Button title="Test iPhone Voice" accessibilityLabel="Test iPhone Voice" onPress={receiver.testVoice} />
        {native && <Button title={mixed ? 'Use direct speech' : 'Use native mixer'} disabled={loading} onPress={changeMode} />}
        {mixed && <Button title="Test mixed audio" onPress={receiver.testMix} />}
        <Button title="Test Open Object Sound" accessibilityLabel="Test Open Object Sound" onPress={receiver.testCue} />
      </View>
      {screen ? <View><Text accessibilityRole="header">Terminal screen</Text>
        <Text selectable style={styles.terminal}>{screen}</Text></View> : null}
      {timing ? <Text style={styles.status}>{timing}</Text> : null}
      {playback ? <Text style={styles.status}>{playback}</Text> : null}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  page: { flexGrow: 1, backgroundColor: 'white', paddingHorizontal: 24, paddingVertical: 68 },
  heading: { fontSize: 28, fontWeight: '600', color: '#111' },
  status: { fontSize: 20, marginVertical: 24, color: '#111' },
  controls: { gap: 20, alignItems: 'flex-start' },
  profile: {alignSelf: 'stretch', gap: 8},
  field: {borderWidth: 1, borderColor: '#666', borderRadius: 4, padding: 10, color: '#111'},
  nativeTerminal: {height: 360},
  keyboard: { height: 108, alignSelf: 'stretch' },
  terminal: { fontFamily: 'Menlo', fontSize: 14, color: '#111' },
});

registerRootComponent(App);
