// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later

let nextConnection = 0;

// A late native callback carries the connection that submitted the work.
// Opening the SSH frame waits for native initialization and reply subscription.
function openWire(native, send, failed) {
  const id = ++nextConnection;
  let live = true, outstanding = 0, bytes = 0;
  const listener = native.addListener('wireReply', event => {
    if (live && event.connection === id) send(event.record);
  });
  const opened = native.open(id);
  return {
    opened,
    record(message, muted) {
      if (!live || !/^[MN] /.test(message)) return;
      // Refuse a stalled consumer at the bridge instead of accumulating
      // calls with transcript content in JavaScript or replaying them later.
      if (outstanding >= 4096 || bytes + message.length > 16 * 1024 * 1024) return failed();
      outstanding++;
      bytes += message.length;
      native.record(id, message[0], message.slice(2), muted).catch(() => { if (live) failed(); })
        .finally(() => { outstanding--; bytes -= message.length; });
    },
    test(sound) { return live ? native.diagnostic(id, sound) : Promise.resolve(false); },
    permission(text) { return live ? native.permission(id, text) : Promise.resolve(false); },
    stopPermission() { if (live) native.stopPermission(id).catch(() => { if (live) failed(); }); },
    stop() { if (live) native.stop(id).catch(() => { if (live) failed(); }); },
    close() {
      if (!live) return;
      live = false;
      listener.remove();
      native.close(id).catch(() => {});
    },
  };
}
module.exports = {openWire};
