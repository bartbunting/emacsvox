// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later

import React, { useEffect, useMemo, useState } from 'react';
import { AppState, Button, ScrollView, StyleSheet, Text, View } from 'react-native';
import { registerRootComponent } from 'expo';
import * as Speech from 'expo-speech';
import { createReceiver } from './receiver';

function App() {
  const [status, setStatus] = useState('Disconnected');
  const [playback, setPlayback] = useState('');
  const receiver = useMemo(() => createReceiver({
    speech: Speech,
    status: setStatus,
    playback: setPlayback,
    openSocket: () => new WebSocket('ws://' + process.env.EXPO_PUBLIC_EMACSVOX_HOST + ':8787/speech'),
  }), []);
  useEffect(() => {
    const listener = AppState.addEventListener('change', state => {
      if (state === 'background') receiver.disconnect();
    });
    return () => { listener.remove(); receiver.disconnect(); };
  }, [receiver]);
  return (
    <ScrollView contentInsetAdjustmentBehavior="automatic" contentContainerStyle={styles.page}>
      <Text accessibilityRole="header" style={styles.heading}>Emacsvox Speech</Text>
      <Text accessibilityLabel={'Connection status. ' + status} style={styles.status}>{status}</Text>
      <View style={styles.controls}>
        <Button title="Connect" accessibilityLabel="Connect" onPress={receiver.connect} />
        <Button title="Disconnect" accessibilityLabel="Disconnect" onPress={() => receiver.disconnect()} />
        <Button title="Stop Speech" accessibilityLabel="Stop Speech" onPress={receiver.stop} />
        <Button title="Test iPhone Voice" accessibilityLabel="Test iPhone Voice" onPress={receiver.testVoice} />
      </View>
      {playback ? <Text style={styles.status}>{playback}</Text> : null}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  page: { flexGrow: 1, backgroundColor: 'white', paddingHorizontal: 24, paddingVertical: 68 },
  heading: { fontSize: 28, fontWeight: '600', color: '#111' },
  status: { fontSize: 20, marginVertical: 24, color: '#111' },
  controls: { gap: 20, alignItems: 'flex-start' },
});

registerRootComponent(App);
