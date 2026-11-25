// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later

// The bundled iOS WebView takes a URI. Everything in this document is local.
const html = String.raw`<!doctype html><html lang="en"><head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; form-action 'none'">
<meta name="color-scheme" content="dark">
<style>
html,body{background:#000;color:#f5f5f5}body{margin:6px;font:18px -apple-system,sans-serif}
textarea{box-sizing:border-box;display:block;width:100%;font:inherit;background:#000;color:#fff;border:1px solid #aaa;padding:6px}
textarea:focus{outline:2px solid #90c4ff}
</style>
</head><body><label for="keys">Emacs keyboard</label>
<textarea id="keys" rows="2" autocomplete="off" autocorrect="off" autocapitalize="off" spellcheck="false"></textarea>
<script>
const field = document.getElementById('keys');
function send(text) {
  // Bound pastes and preserve surrogate pairs at packet boundaries.
  let packet = '';
  for (const char of text) {
    if (packet.length + char.length > 256) {
      window.ReactNativeWebView.postMessage(packet);
      packet = '';
    }
    packet += char;
  }
  if (packet) window.ReactNativeWebView.postMessage(packet);
}
const basic = {Enter:'\r', Escape:'\x1b', Tab:'\t', Backspace:'\x7f'};
const cursor = {ArrowUp:'A', ArrowDown:'B', ArrowRight:'C', ArrowLeft:'D', Home:'H', End:'F'};
const functionKeys = {F1:'P', F2:'Q', F3:'R', F4:'S'};
const tildeKeys = {Insert:2, Delete:3, PageUp:5, PageDown:6, F5:15, F6:17, F7:18,
  F8:19, F9:20, F10:21, F11:23, F12:24};
const punctuation = {Comma:',<', Period:'.>', Slash:'/?', Semicolon:';:', Quote:"'\"",
  BracketLeft:'[{', BracketRight:']}', Backslash:'\\|', Minus:'-_', Equal:'=+', Backquote:'\x60~'};

// Prefer the symbol from the active layout. Fall back to the physical US
// position when Option changes the character to a glyph or a dead key.
function metaCharacter(event, shift) {
  const code = event.code;
  const pair = Object.hasOwn(punctuation, code) && punctuation[code];
  if (shift && pair && event.key === pair[0]) return pair[1];
  if (/^[\x20-\x7e]$/.test(event.key)) return event.key;
  if (shift && (!code || code === 'Unidentified')) {
    if (event.key === '¯') return '<';
    if (event.key === '˘') return '>';
  }
  if (/^Key[A-Z]$/.test(code)) {
    const letter = code.slice(3);
    return shift ? letter : letter.toLowerCase();
  }
  if (/^Digit[0-9]$/.test(code)) return shift ? ')!@#$%^&*('[code[5]] : code[5];
  if (pair) return pair[shift ? 1 : 0];
}

function terminalKey(event) {
  const {altKey, ctrlKey} = event;
  const shiftKey = event.shiftKey || event.getModifierState?.('Shift');
  let key = event.key;
  if (!event.metaKey && ctrlKey && shiftKey) {
    // WebKit sometimes reports a control byte instead of the letter.
    const letter = /^[a-z]$/i.test(key) ? key :
      /^Key[A-Z]$/.test(event.code) ? event.code.slice(3) : '';
    if (letter) return '\x1b[' + letter.toLowerCase().charCodeAt(0) + (altKey ? ';8u' : ';6u');
  }
  if (!event.metaKey && ctrlKey && /^Key[A-Z]$/.test(event.code) && /^[\x00-\x1f]$/.test(key)) {
    return (altKey ? '\x1b' : '') + key;
  }
  if (key === 'Return' || key === '\r' || key === '\n' ||
      ((!key || key === 'Unidentified') && (event.code === 'Enter' || event.code === 'NumpadEnter'))) {
    key = 'Enter';
  }
  const hyper = event.metaKey && window.emacsCommandHyper;
  const mod = 1 + (hyper ? 16 : 0) + (shiftKey ? 1 : 0) + (altKey ? 2 : 0) + (ctrlKey ? 4 : 0);
  if (Object.hasOwn(cursor, key) || Object.hasOwn(functionKeys, key)) {
    const suffix = cursor[key] ?? functionKeys[key];
    if (mod === 1) return (cursor[key] ? '\x1b[' : '\x1bO') + suffix;
    return '\x1b[1;' + mod + suffix;
  }
  if (Object.hasOwn(tildeKeys, key)) return '\x1b[' + tildeKeys[key] + (mod === 1 ? '' : ';' + mod) + '~';
  if (hyper) {
    const raw = basic[key] ?? metaCharacter(event, shiftKey);
    if (!raw || raw.length !== 1) return;
    const letter = /^[A-Za-z]$/.test(raw);
    const code = (letter ? raw.toLowerCase() : raw).charCodeAt(0);
    // Shifted punctuation already carries its symbol, e.g. Hyper+greater-than.
    const modifier = shiftKey && !letter && !Object.hasOwn(basic, key) ? mod - 1 : mod;
    return '\x1b[' + code + ';' + modifier + 'u';
  }
  const esc = altKey ? '\x1b' : '';
  if (Object.hasOwn(basic, key)) {
    if ((ctrlKey || shiftKey) && (key === 'Backspace' || key === 'Escape')) {
      return '\x1b[' + basic[key].charCodeAt(0) + ';' + mod + 'u';
    }
    if ((ctrlKey || shiftKey) && (key === 'Enter' || key === 'Tab')) {
      if (!ctrlKey && key === 'Tab') return esc + '\x1b[Z';
      return esc + '\x1b[27;' + (1 + (ctrlKey ? 4 : 0) + (shiftKey ? 1 : 0)) + ';' + basic[key].charCodeAt(0) + '~';
    }
    return esc + basic[key];
  }
  // Forward ordinary hardware keys before the text field can echo them.
  // The layout supplies the character. Text composition still uses input.
  if (event.cancelable !== false && !ctrlKey && !altKey && event.code && event.code !== 'Unidentified' &&
      key && Array.from(key).length === 1 && !/[\x00-\x1f\x7f-\x9f]/.test(key)) return key;
  const char = altKey ? metaCharacter(event, shiftKey) : key;
  if (!char || char.length !== 1) return;
  if (ctrlKey) {
    const upper = char.toUpperCase();
    if (char === ' ' || char === '@') return esc + '\x00';
    if (char === '?') return esc + '\x7f';
    if (!altKey && !shiftKey && /^[2-8]$/.test(char)) return '\x00\x1b\x1c\x1d\x1e\x1f\x7f'[Number(char) - 2];
    if (upper.length === 1 && upper >= '@' && upper <= '_') return esc + String.fromCharCode(upper.charCodeAt(0) & 31);
    if (/^[\x21-\x7e]$/.test(char)) return '\x1b[27;' + mod + ';' + char.charCodeAt(0) + '~';
  } else if (altKey) return esc + char;
}
field.addEventListener('keydown', event => {
  if (event.isComposing || event.keyCode === 229 || (event.metaKey && !window.emacsCommandHyper) ||
      (!event.altKey && event.getModifierState?.('AltGraph')) || (event.altKey && event.ctrlKey &&
      (!window.emacsControlOption || event.getModifierState?.('AltGraph')))) return;
  const bytes = terminalKey(event);
  if (bytes !== undefined) { event.preventDefault(); send(bytes); }
});
function flushText() {
  const text = field.value;
  field.value = '';
  send(text);
}
field.addEventListener('input', event => { if (!event.isComposing) flushText(); });
field.addEventListener('compositionend', flushText);
</script></body></html>`;

// Give each new input one focus request. Returning from Settings or Stop
// during the same session should leave the VoiceOver cursor where it is.
function createKeyboardFocus() {
  let lastInput;
  return (input, visible, focus) => {
    if (!input) { lastInput = null; return; }
    if (!visible || input === lastInput) return;
    lastInput = input;
    focus(input);
  };
}

module.exports = {keyboardSource: {uri: 'data:text/html;charset=utf-8,' + encodeURIComponent(html)}, createKeyboardFocus};
