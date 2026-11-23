// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later

let nextConnection = 0;

// A late native callback carries the connection that submitted the work.
// Opening the SSH frame waits for native initialization and reply subscription.
function openWire(native, send, failed) {
  const id = ++nextConnection;
  let live = true, outstanding = 0, bytes = 0;
  let lastSerial = 0, trial = null;
  const listener = native.addListener('wireReply', event => {
    if (live && event.connection === id) send(event.record);
  });
  function cancelTiming(reason = 'Timing cancelled.') {
    if (!trial) return;
    clearTimeout(trial.timer);
    trial.reject?.(new Error(reason));
    trial = null;
    native.armKeyTiming(id, 0).catch(() => {});
  }
  const timingListener = native.armKeyTiming && native.addListener('keyTiming', event => {
    if (!live || event.connection !== id || event.serial !== trial?.serial || !trial?.resolve ||
        trial.received == null || !Number.isFinite(event.time) || event.time < trial.received ||
        !['buffer', 'speech'].includes(event.event)) return;
    const done = trial;
    trial = null;
    clearTimeout(done.timer);
    done.resolve({returned: Math.round(done.received - done.started),
      audio: Math.round(event.time - done.started), event: event.event});
  });
  const opened = native.open(id);
  function record(message, muted) {
    if (!live || !/^[MN] /.test(message)) return;
    // Refuse a stalled consumer at the bridge instead of accumulating
    // calls with transcript content in JavaScript or replaying them later.
    if (outstanding >= 4096 || bytes + message.length > 16 * 1024 * 1024) return failed();
    if (!muted && trial?.resolve && trial.received == null && message === trial.record) {
      trial.received = native.timingClock();
    }
    outstanding++;
    bytes += message.length;
    native.record(id, message[0], message.slice(2), muted).catch(() => { if (live) failed(); })
      .finally(() => { outstanding--; bytes -= message.length; });
  }
  async function prepareTiming(local) {
    cancelTiming();
    if (!live || !timingListener || lastSerial >= 255) throw new Error('Reconnect to start a timing test.');
    const serial = ++lastSerial;
    const sample = {serial, record: 'M q {timing sample ' + serial + ' }'};
    trial = sample;
    try { await native.armKeyTiming(id, serial); }
    catch (error) { if (trial === sample) cancelTiming(); throw error; }
    if (trial !== sample) throw new Error('Timing cancelled.');
    return sendKey => new Promise((resolve, reject) => {
      if (trial !== sample || sample.resolve) return reject(new Error('Timing cancelled.'));
      sample.started = native.timingClock();
      Object.assign(sample, {resolve, reject});
      sample.timer = setTimeout(() => {
        if (trial !== sample) return;
        cancelTiming(sample.received == null ? 'No matching speech returned from Emacs.' : 'No matching audio started.');
      }, 8000);
      if (local) {
        record(sample.record, false);
        record('M d', false);
      } else {
        Promise.resolve().then(() => { if (trial === sample) return sendKey('\x1b[57343;' + serial + 'u'); })
          .catch(() => { if (trial === sample) cancelTiming('Could not send the test key.'); });
      }
    });
  }
  return {
    opened, record, prepareTiming, cancelTiming,
    test(sound) { return live ? native.diagnostic(id, sound) : Promise.resolve(false); },
    permission(text) { return live ? native.permission(id, text) : Promise.resolve(false); },
    stopPermission() { if (live) native.stopPermission(id).catch(() => { if (live) failed(); }); },
    stop() { cancelTiming(); if (live) native.stop(id).catch(() => { if (live) failed(); }); },
    close() {
      if (!live) return;
      cancelTiming();
      live = false;
      listener.remove();
      timingListener?.remove();
      native.close(id).catch(() => {});
    },
  };
}
module.exports = {openWire};
