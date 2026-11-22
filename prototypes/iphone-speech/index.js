// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later

import React, { useEffect, useMemo, useState } from 'react';
import { AppState, Button, ScrollView, StyleSheet, Text, View } from 'react-native';
import { registerRootComponent, requireOptionalNativeModule } from 'expo';
import { Asset } from 'expo-asset';
import { mixerAdapters } from './mixer';
import { useAudioPlayer } from 'expo-audio';
import * as Speech from 'expo-speech';
import { createReceiver } from './receiver';
import { WebView } from '@expo/dom-webview';
import { keyboardSource } from './keyboard';

const native = requireOptionalNativeModule('IphoneMixer');
const sound = require('./assets/open-object.wav');

function App() {
  const [mixed, setMixed] = useState(false);
  return <Session key={String(mixed)} mixed={mixed} switchMode={() => setMixed(value => !value)} />;
}

function Session({mixed, switchMode}) {
  const [status, setStatus] = useState('Disconnected');
  const [playback, setPlayback] = useState('');
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
    openSocket: () => new WebSocket('ws://' + process.env.EXPO_PUBLIC_EMACSVOX_HOST + ':' +
      (process.env.EXPO_PUBLIC_EMACSVOX_PORT || '8787') + '/speech'),
  }), [adapters]);
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
        <Button title="Connect" accessibilityLabel="Connect" onPress={receiver.connect} />
        <Button title="Disconnect" accessibilityLabel="Disconnect" onPress={() => receiver.disconnect()} />
        <Button title="Stop Speech" accessibilityLabel="Stop Speech" onPress={receiver.stop} />
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
  keyboard: { height: 108, alignSelf: 'stretch' },
  terminal: { fontFamily: 'Menlo', fontSize: 14, color: '#111' },
});

registerRootComponent(App);
