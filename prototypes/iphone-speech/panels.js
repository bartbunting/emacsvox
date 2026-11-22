// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later

import React, {useRef} from 'react';
import {AccessibilityInfo, Button, Modal, ScrollView, StyleSheet, Switch, Text, TextInput, View} from 'react-native';

export const colors = {background: '#000', text: '#f5f5f5', action: '#90c4ff'};

export function Action(props) {
  return <Button color={colors.action} {...props} />;
}

export function Panel({title, close, onDismiss, children}) {
  const heading = useRef(null);
  // Keep the terminal attached to its window while the panel covers it.
  return <Modal visible transparent presentationStyle="overFullScreen" animationType="none"
    onRequestClose={close} onDismiss={onDismiss}
    onShow={() => { if (heading.current) AccessibilityInfo.sendAccessibilityEvent(heading.current, 'focus'); }}>
    <ScrollView style={styles.surface} contentContainerStyle={styles.panel}
      contentInsetAdjustmentBehavior="automatic" keyboardShouldPersistTaps="handled"
      accessibilityViewIsModal onAccessibilityEscape={close}>
      <Text ref={heading} accessibilityRole="header" style={styles.heading}>{title}</Text>
      {children}
    </ScrollView>
  </Modal>;
}

function Toggle({label, hint, value, change}) {
  return <View style={styles.toggle}>
    <Text accessible={false} accessibilityElementsHidden style={styles.label}>{label}</Text>
    <Switch accessibilityLabel={label} accessibilityHint={hint}
      value={value} onValueChange={change} />
  </View>;
}

export function Settings({draft, edit, save, cancel, onDismiss, ssh, mixer}) {
  const [message, setMessage] = React.useState('');
  return <Panel title="Settings" close={cancel} onDismiss={onDismiss}>
    <Action title="Save settings" onPress={save} />
    <Action title="Cancel" onPress={cancel} />
    {ssh && <>
      <Toggle label="Use SSH terminal" hint="Connect your external keyboard to Emacs through SSH. Switch off to use the test relay."
        value={draft.transport === 'ssh'} change={v => edit('transport', v ? 'ssh' : 'relay')} />
      <Toggle label="Use Emacs keyboard field" hint="Use the keyboard field that was tested with VoiceOver. Switch off to type directly into SwiftTerm."
        value={draft.input === 'field'} change={v => edit('input', v ? 'field' : 'terminal')} />
      <Toggle label="Keep awake while connected" hint="Prevent automatic screen lock while this app is in the foreground."
        value={draft.keepAwake === 'yes'} change={v => edit('keepAwake', v ? 'yes' : 'no')} />
      {[['host','WSL Tailscale IPv4 address'], ['port','SSH port'], ['username','WSL username'],
        ['pin','Trusted WSL host public key']].map(([name,label]) => <View key={name}>
        <Text accessible={false} accessibilityElementsHidden style={styles.label}>{label}</Text>
        <TextInput accessibilityLabel={label} autoCapitalize="none" autoCorrect={false}
          keyboardAppearance="dark" selectionColor={colors.action} style={styles.field}
          value={draft[name]} onChangeText={v => edit(name, v)} />
      </View>)}
      <Action title="Copy iPhone SSH public key" onPress={async () => {
        try { await ssh.copyPublicKey(); setMessage('iPhone public key copied.'); }
        catch { setMessage('Could not read the iPhone SSH identity.'); }
      }} />
    </>}
    {mixer && <Toggle label="Use native mixer" hint="Mix local speech with tones and earcons. Switch off for direct iPhone speech."
      value={draft.audio === 'mixed'} change={v => edit('audio', v ? 'mixed' : 'direct')} />}
    {message ? <Text style={styles.label}>{message}</Text> : null}
  </Panel>;
}

const styles = StyleSheet.create({
  surface: {backgroundColor: colors.background},
  panel: {flexGrow: 1, gap: 18, paddingHorizontal: 24, paddingVertical: 40},
  heading: {fontSize: 28, fontWeight: '600', color: colors.text},
  label: {fontSize: 18, color: colors.text, flexShrink: 1},
  toggle: {flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 12, minHeight: 44},
  field: {color: colors.text, borderColor: '#aaa', borderWidth: 1, padding: 10, marginTop: 6, borderRadius: 4},
});
