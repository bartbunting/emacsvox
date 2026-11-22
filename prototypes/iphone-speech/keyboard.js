// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later

// The bundled iOS WebView takes a URI. Everything in this document is local.
const html = String.raw`<!doctype html><html lang="en"><head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; form-action 'none'">
<style>body{margin:6px;font:18px -apple-system,sans-serif} textarea{box-sizing:border-box;display:block;width:100%;font:inherit;border:1px solid;padding:6px}</style>
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
const special = {Enter:'\r', Escape:'\x1b', Tab:'\t', Backspace:'\x7f', Delete:'\x1b[3~',
  ArrowUp:'\x1b[A', ArrowDown:'\x1b[B', ArrowRight:'\x1b[C', ArrowLeft:'\x1b[D',
  Home:'\x1b[H', End:'\x1b[F', PageUp:'\x1b[5~', PageDown:'\x1b[6~'};
field.addEventListener('keydown', event => {
  if (event.isComposing || event.metaKey || (event.altKey && event.ctrlKey)) return;
  let bytes;
  if (event.altKey) {
    let letter = event.key;
    if (!/^[a-zA-Z]$/.test(letter)) {
      // Option can produce a symbol such as ƒ on the physical F key.
      if (!/^Key[A-Z]$/.test(event.code)) return;
      letter = event.code.slice(3);
      if (!event.shiftKey) letter = letter.toLowerCase();
    }
    bytes = '\x1b' + letter;
  } else if (event.ctrlKey) {
    const k = event.key.toUpperCase();
    if (k === ' ') bytes = '\x00';
    else if (k === '?') bytes = '\x7f';
    else if (k.length === 1 && k >= '@' && k <= '_') bytes = String.fromCharCode(k.charCodeAt(0) & 31);
  } else if (Object.hasOwn(special, event.key)) {
    bytes = event.key === 'Tab' && event.shiftKey ? '\x1b[Z' : special[event.key];
  }
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

module.exports = { keyboardSource: {uri: 'data:text/html;charset=utf-8,' + encodeURIComponent(html)} };
