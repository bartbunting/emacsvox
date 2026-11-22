// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later

const vm = require('node:vm');
const { keyboardSource } = require('../keyboard');

// Run the document shipped to the WebView, with its normal postMessage boundary.
function keyboardField(postMessage, controlOption = false) {
  const listeners = {};
  const field = {value: '', addEventListener(name, fn) { listeners[name] = fn; }};
  const html = decodeURIComponent(keyboardSource.uri.split(',')[1]);
  vm.runInNewContext(html.match(/<script>([\s\S]*?)<\/script>/)[1], {
    document: {getElementById: () => field},
    window: {ReactNativeWebView: {postMessage}, emacsControlOption: controlOption},
  });
  function down(key, modifiers) {
    let prevented = false;
    listeners.keydown({key, ...modifiers, preventDefault() { prevented = true; }});
    return prevented;
  }
  return {field, listeners, down};
}
module.exports = { keyboardField };
