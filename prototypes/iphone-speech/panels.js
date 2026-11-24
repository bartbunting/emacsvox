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

export function Section({title, hint, selected, select, children}) {
  const open = selected === title;
  return <>
    <Pressable accessibilityRole="button" accessibilityLabel={title} accessibilityHint={hint}
      accessibilityState={{expanded: open}} onPress={() => select(open ? '' : title)}
      style={styles.sectionButton}>
      <Text style={styles.sectionTitle}>{title}</Text>
      <Text accessible={false} accessibilityElementsHidden style={styles.sectionTitle}>{open ? '−' : '+'}</Text>
    </Pressable>
    {open && children}
  </>;
}

function Field({label, hint, value, change, numeric}) {
  return <View>
    <Text accessible={false} accessibilityElementsHidden style={styles.label}>{label}</Text>
    <TextInput accessibilityLabel={label} accessibilityHint={hint} keyboardType={numeric ? 'number-pad' : 'default'}
      autoCapitalize="none" autoCorrect={false} keyboardAppearance="dark" selectionColor={colors.action}
      style={styles.field} value={value} onChangeText={change} />
  </View>;
}

export function Settings({draft, edit, save, cancel, ssh, mixer, wire, LoudnessSlider, AudioRoutePicker}) {
  const [message, setMessage] = React.useState('');
  const [selected, select] = React.useState('');
  const sections = {selected, select};
  const terminal = ssh && draft.transport === 'ssh';
  const omnivox = wire && terminal && draft.worker === 'omnivox';
  function report(detail) {
    setMessage(detail);
    AccessibilityInfo.announceForAccessibility?.(detail);
  }
  function saveSettings() {
    const columns = draft.terminalColumns?.trim();
    if (terminal && !(columns === '0' || (/^\d{2,3}$/.test(columns) && Number(columns) >= 40 && Number(columns) <= 240))) {
      select('Keyboard and terminal');
      report('Enter 40 to 240 terminal columns, or zero to fit the screen.');
    } else save();
  }
  return <TabPage title="Settings">
    <Section title="Connection" hint="WSL address, SSH identity and automatic connection." {...sections}>
      {ssh && <Toggle label="Use SSH terminal" hint="Connect your external keyboard to Emacs through SSH. Switch off to use the test relay."
        value={draft.transport === 'ssh'} change={v => edit('transport', v ? 'ssh' : 'relay')} />}
      <Field label="WSL Tailscale IPv4 address" value={draft.host} change={v => edit('host', v)} />
      {terminal && <>
        <Field label="SSH port" numeric value={draft.port} change={v => edit('port', v)} />
        <Field label="WSL username" value={draft.username} change={v => edit('username', v)} />
        <Field label="Trusted WSL host public key" value={draft.pin} change={v => edit('pin', v)} />
      </>}
      {ssh && <>
        <Toggle label="Connect on open" hint="Connect to the saved SSH host when you launch the app."
          value={draft.connectOnOpen === 'yes'} change={v => edit('connectOnOpen', v ? 'yes' : 'no')} />
        <Action title="Copy iPhone SSH public key" onPress={async () => {
          try { await ssh.copyPublicKey(); report('iPhone public key copied.'); }
          catch { report('Could not read the iPhone SSH identity.'); }
        }} />
      </>}
    </Section>
    {ssh && <Section title="Keyboard and terminal" hint="Keyboard input, modifiers, line width, screen lock and web links." {...sections}>
      <Toggle label="Use Emacs keyboard field" hint="Use an editable VoiceOver field. Switch off to type directly into SwiftTerm."
        value={draft.input === 'field'} change={v => edit('input', v ? 'field' : 'terminal')} />
      {terminal && <Toggle label="Use Windows or Command as Emacs Hyper"
        hint="Hold this key with another key in the terminal to send Hyper. iOS or VoiceOver may reserve some shortcuts."
        value={draft.commandHyper === 'yes'} change={v => edit('commandHyper', v ? 'yes' : 'no')} />}
      {draft.input === 'field' && <Toggle label="Send Control+Option to Emacs"
        hint="Choose Caps Lock as your VoiceOver modifier first. When off, press Escape followed by the Control key combination."
        value={draft.controlOption === 'emacs'} change={v => edit('controlOption', v ? 'emacs' : 'voiceover')} />}
      {terminal && <Field label="Minimum terminal columns" numeric value={draft.terminalColumns} change={v => edit('terminalColumns', v)}
        hint="Enter 40 to 240, or zero to fit the screen. Wider lines shrink the terminal print. Review terminal screen keeps your usual text size." />}
      <Toggle label="Keep awake while connected" hint="Prevent automatic screen lock while this app is in the foreground."
        value={draft.keepAwake === 'yes'} change={v => edit('keepAwake', v ? 'yes' : 'no')} />
      {ssh.hasWebBrowser && omnivox && <Toggle label="Open web links inside Emacsvox Speech"
        hint="Use Done in the Safari view to return to Emacs. Turn off to use your default browser."
        value={draft.webBrowser !== 'external'} change={v => edit('webBrowser', v ? 'in-app' : 'external')} />}
    </Section>}
    {(wire || mixer) && <Section title="Speech and sounds" hint="Speech engine, audio output, loudness, earcons and optional speech logging." {...sections}>
      {wire && terminal && <Toggle label="Use Omnivox on iPhone" hint="Run speech, voice discovery, tones and earcons on this phone. Saving reconnects the terminal."
        value={draft.worker === 'omnivox'} change={v => edit('worker', v ? 'omnivox' : 'legacy')} />}
      {LoudnessSlider && omnivox && <>
        <Text accessible={false} accessibilityElementsHidden style={styles.label}>Speech loudness · {Number(draft.speechLoudness) || 0} dB</Text>
        <LoudnessSlider style={{height: 48}} level={Number(draft.speechLoudness) || 0}
          onLevelChange={({nativeEvent}) => edit('speechLoudness', String(nativeEvent.decibels))} />
      </>}
      {AudioRoutePicker && <View style={styles.toggle}>
        <Text style={styles.label}>Audio output for speech and notifications</Text>
        <AudioRoutePicker style={{width: 52, height: 48}} />
      </View>}
      {mixer && !omnivox && <Toggle label="Use native mixer" hint="Mix local speech with tones and earcons. Switch off for direct iPhone speech."
        value={draft.audio === 'mixed'} change={v => edit('audio', v ? 'mixed' : 'direct')} />}
      {wire && <Action title="Import a personal earcon" onPress={async () => {
        try { if (await wire.importCue()) report('Earcon imported. Emacs can now play the matching recording.'); }
        catch { report('Could not import this recording. Choose a WAV or OGG up to 16 MiB and 30 seconds.'); }
      }} />}
      {wire?.setSpeechLogging && <Toggle label="Log speech text and timing"
        hint="Save to start recording on this phone. Diagnostics can send the trace to WSL. Save with the switch off to erase the phone copy."
        value={draft.logSpeech === 'yes'} change={v => edit('logSpeech', v ? 'yes' : 'no')} />}
    </Section>}
    {message ? <Text style={styles.label}>{message}</Text> : null}
    <Action title="Save settings" onPress={saveSettings} />
    <Action title="Cancel" onPress={cancel} />
  </TabPage>;
}

const styles = StyleSheet.create({
  surface: {backgroundColor: colors.background},
  panel: {flexGrow: 1, gap: 18, paddingHorizontal: 24, paddingVertical: 40},
  heading: {fontSize: 28, fontWeight: '600', color: colors.text},
  label: {fontSize: 18, color: colors.text, flexShrink: 1},
  sectionButton: {flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center',
    minHeight: 48, borderBottomColor: '#636366', borderBottomWidth: StyleSheet.hairlineWidth},
  sectionTitle: {fontSize: 18, color: colors.action},
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
