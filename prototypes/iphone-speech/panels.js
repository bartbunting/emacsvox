// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later

import React, {useEffect, useRef} from 'react';
import {AccessibilityInfo, Button, Modal, Pressable, ScrollView, StyleSheet, Switch, Text, TextInput, View} from 'react-native';

export const colors = {background: '#000', text: '#f5f5f5', action: '#90c4ff'};

export function Action(props) {
  return <Button color={colors.action} {...props} />;
}

export function TabBar({selected, onSelect}) {
  return <View accessible={false} collapsable={false} accessibilityRole="tabbar" style={styles.tabs}>
    {['Terminal', 'Diagnostics', 'Settings'].map(name => {
      const active = selected === name;
      return <Pressable key={name} accessibilityRole="tab" accessibilityLabel={name}
        accessibilityState={{selected: active}} onPress={() => onSelect(name)}
        style={[styles.tab, active && styles.selectedTab]}>
        <Text style={[styles.tabLabel, active && styles.selectedLabel]}>{name}</Text>
      </Pressable>;
    })}
  </View>;
}

export function TabPage({title, children}) {
  const heading = useRef(null);
  useEffect(() => {
    const id = requestAnimationFrame(() => {
      if (heading.current) AccessibilityInfo.sendAccessibilityEvent(heading.current, 'focus');
    });
    return () => cancelAnimationFrame(id);
  }, [title]);
  return <ScrollView style={styles.surface} contentContainerStyle={styles.panel}
    keyboardShouldPersistTaps="handled">
    <Text ref={heading} accessibilityRole="header" style={styles.heading}>{title}</Text>
    {children}
  </ScrollView>;
}

function Panel({title, close, children}) {
  const heading = useRef(null);
  // Keep the terminal attached to its window while the panel covers it.
  return <Modal visible transparent presentationStyle="overFullScreen" animationType="none"
    onRequestClose={close}
    onShow={() => { if (heading.current) AccessibilityInfo.sendAccessibilityEvent(heading.current, 'focus'); }}>
    <ScrollView style={styles.surface} contentContainerStyle={styles.panel}
      contentInsetAdjustmentBehavior="automatic" keyboardShouldPersistTaps="handled"
      accessibilityViewIsModal onAccessibilityEscape={close}>
      <Text ref={heading} accessibilityRole="header" style={styles.heading}>{title}</Text>
      {children}
    </ScrollView>
  </Modal>;
}

export function TerminalReview({terminalRef, frame, close}) {
  const [rows, setRows] = React.useState(null);
  const [failed, setFailed] = React.useState(false);
  React.useEffect(() => {
    let open = true;
    const terminal = terminalRef.current;
    if (terminal) {
      terminal.visibleRows(frame).then(value => { if (open) setRows(value); },
        () => { if (open) setFailed(true); });
    } else setFailed(true);
    return () => { open = false; };
  }, [terminalRef, frame]);
  return <Panel title="Terminal screen" close={close}>
    <Action title="Done" onPress={close} />
    {failed ? <Text style={styles.label}>Terminal unavailable.</Text>
      : rows === null ? <Text style={styles.label}>Reading the screen.</Text>
      : rows.length ? rows.map((row, index) => <Text key={index} style={styles.row}>{row}</Text>)
      : <Text style={styles.label}>The terminal screen is blank.</Text>}
  </Panel>;
}

function Toggle({label, hint, value, change}) {
  return <View style={styles.toggle}>
    <Text accessible={false} accessibilityElementsHidden style={styles.label}>{label}</Text>
    <Switch accessibilityLabel={label} accessibilityHint={hint}
      value={value} onValueChange={change} />
  </View>;
}

export function Settings({draft, edit, save, cancel, ssh, mixer, wire, LoudnessSlider}) {
  const [message, setMessage] = React.useState('');
  const fields = [['host', 'WSL Tailscale IPv4 address']];
  if (ssh && draft.transport === 'ssh') {
    fields.push(['terminalColumns', 'Minimum terminal columns'], ['port', 'SSH port'], ['username', 'WSL username'], ['pin', 'Trusted WSL host public key']);
  }
  return <TabPage title="Settings">
    <Action title="Save settings" onPress={() => {
      const columns = draft.terminalColumns?.trim();
      if (ssh && draft.transport === 'ssh' &&
          !(columns === '0' || (/^\d{2,3}$/.test(columns) && Number(columns) >= 40 && Number(columns) <= 240))) {
        const detail = 'Enter 40 to 240 terminal columns, or zero to fit the screen.';
        setMessage(detail);
        AccessibilityInfo.announceForAccessibility(detail);
      } else save();
    }} />
    <Action title="Cancel" onPress={cancel} />
    {ssh && <>
      <Toggle label="Use SSH terminal" hint="Connect your external keyboard to Emacs through SSH. Switch off to use the test relay."
        value={draft.transport === 'ssh'} change={v => edit('transport', v ? 'ssh' : 'relay')} />
      {wire && draft.transport === 'ssh' && <Toggle label="Use Omnivox on iPhone"
        hint="Run speech, installed voice discovery, tones and earcons on this phone. Reconnects the terminal when saved."
        value={draft.worker === 'omnivox'} change={v => edit('worker', v ? 'omnivox' : 'legacy')} />}
      {ssh.hasWebBrowser && draft.worker === 'omnivox' && draft.transport === 'ssh' &&
        <Toggle label="Open web links inside Emacsvox Speech"
          hint="Use Done in the Safari view to return to Emacs. Turn off to open links in the default browser on this iPhone."
          value={draft.webBrowser !== 'external'} change={v => edit('webBrowser', v ? 'in-app' : 'external')} />}
      {LoudnessSlider && draft.transport === 'ssh' && draft.worker === 'omnivox' && <>
        <Text accessible={false} accessibilityElementsHidden style={styles.label}>Speech loudness · {Number(draft.speechLoudness) || 0} dB</Text>
        <LoudnessSlider style={{height: 48}} level={Number(draft.speechLoudness) || 0}
          onLevelChange={({nativeEvent}) => edit('speechLoudness', String(nativeEvent.decibels))} />
      </>}
      {wire?.setSpeechLogging && <Toggle label="Log speech text and timing"
        hint="Save to start recording on this phone. Use Diagnostics to read the trace or send a copy to WSL. Save with the switch off to erase the phone copy."
        value={draft.logSpeech === 'yes'} change={v => edit('logSpeech', v ? 'yes' : 'no')} />}
      <Toggle label="Connect on open" hint="Open the saved SSH connection when you launch the app. The Emacs keyboard receives focus once the terminal is ready."
        value={draft.connectOnOpen === 'yes'} change={v => edit('connectOnOpen', v ? 'yes' : 'no')} />
      <Toggle label="Use Emacs keyboard field" hint="Use the keyboard field that was tested with VoiceOver. Switch off to type directly into SwiftTerm."
        value={draft.input === 'field'} change={v => edit('input', v ? 'field' : 'terminal')} />
      {draft.transport === 'ssh' && <Toggle label="Use Windows or Command as Emacs Hyper"
        hint="Hold this key with another key in the terminal to send Hyper. iOS or VoiceOver may reserve some shortcuts."
        value={draft.commandHyper === 'yes'} change={v => edit('commandHyper', v ? 'yes' : 'no')} />}
      {draft.input === 'field' && <Toggle label="Send Control+Option to Emacs"
        hint="Use Control and Meta together in the Emacs keyboard field. Choose Caps Lock as your VoiceOver modifier first. When off, press Escape followed by the Control key combination."
        value={draft.controlOption === 'emacs'} change={v => edit('controlOption', v ? 'emacs' : 'voiceover')} />}
      <Toggle label="Keep awake while connected" hint="Prevent automatic screen lock while this app is in the foreground."
        value={draft.keepAwake === 'yes'} change={v => edit('keepAwake', v ? 'yes' : 'no')} />
    </>}
    {fields.map(([name,label]) => <View key={name}>
      <Text accessible={false} accessibilityElementsHidden style={styles.label}>{label}</Text>
      <TextInput accessibilityLabel={label}
        accessibilityHint={name === 'terminalColumns' ? 'Enter 40 to 240, or zero to fit the screen. Wider lines shrink the terminal print. Review terminal screen keeps your usual text size.' : undefined}
        keyboardType={name === 'terminalColumns' ? 'number-pad' : 'default'} autoCapitalize="none" autoCorrect={false}
        keyboardAppearance="dark" selectionColor={colors.action} style={styles.field}
        value={draft[name]} onChangeText={v => edit(name, v)} />
    </View>)}
    {ssh && <Action title="Copy iPhone SSH public key" onPress={async () => {
      try { await ssh.copyPublicKey(); setMessage('iPhone public key copied.'); }
      catch { setMessage('Could not read the iPhone SSH identity.'); }
    }} />}
    {wire && <Action title="Import a personal earcon" onPress={async () => {
      try { if (await wire.importCue()) setMessage('Earcon imported. Emacs can now play the matching recording.'); }
      catch { setMessage('Could not import this recording. Choose a WAV or OGG up to 16 MiB and 30 seconds.'); }
    }} />}
    {mixer && !(wire && draft.transport === 'ssh' && draft.worker === 'omnivox') && <Toggle label="Use native mixer" hint="Mix local speech with tones and earcons. Switch off for direct iPhone speech."
      value={draft.audio === 'mixed'} change={v => edit('audio', v ? 'mixed' : 'direct')} />}
    {message ? <Text style={styles.label}>{message}</Text> : null}
  </TabPage>;
}

const styles = StyleSheet.create({
  surface: {backgroundColor: colors.background},
  panel: {flexGrow: 1, gap: 18, paddingHorizontal: 24, paddingVertical: 40},
  heading: {fontSize: 28, fontWeight: '600', color: colors.text},
  label: {fontSize: 18, color: colors.text, flexShrink: 1},
  row: {fontFamily: 'Menlo', fontSize: 16, color: colors.text},
  toggle: {flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 12, minHeight: 44},
  field: {color: colors.text, borderColor: '#aaa', borderWidth: 1, padding: 10, marginTop: 6, borderRadius: 4},
  tabs: {flexDirection: 'row', borderTopColor: '#636366', borderTopWidth: StyleSheet.hairlineWidth},
  tab: {flex: 1, minHeight: 48, alignItems: 'center', justifyContent: 'center',
    paddingHorizontal: 2, paddingVertical: 8, borderTopWidth: 3, borderTopColor: 'transparent'},
  selectedTab: {borderTopColor: colors.action},
  tabLabel: {fontSize: 16, textAlign: 'center', color: colors.text},
  selectedLabel: {color: colors.action, fontWeight: '700'},
});
