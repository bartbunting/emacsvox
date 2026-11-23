// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later

const {once} = require('node:events');
const net = require('node:net');
const path = require('node:path');

const recordLimit = 512 * 1024;
const decoder = new TextDecoder('utf-8', {fatal: true, ignoreBOM: true});

// Keep at most one partial record per stream. A rejected record is drained
// through LF. Its last fragment can never become a command on its own.
class Records {
  constructor(accept) {
    this.accept = accept;
    this.parts = [];
    this.length = 0;
    this.drain = false;
  }

  write(bytes) {
    let start = 0;
    while (start < bytes.length) {
      const lf = bytes.indexOf(10, start);
      const part = bytes.subarray(start, lf < 0 ? bytes.length : lf);
      this.length += part.length;
      if (this.length > recordLimit + 1) {
        this.parts = [];
        this.drain = true;
      }
      if (!this.drain && part.length) this.parts.push(part);
      if (lf < 0) return;
      if (!this.drain) {
        let line = Buffer.concat(this.parts, this.length);
        if (line.at(-1) === 13) line = line.subarray(0, -1);
        if (line.length <= recordLimit) {
          let text;
          try { text = decoder.decode(line); } catch { /* Invalid UTF-8 record. */ }
          if (text !== undefined) this.accept(text);
        }
      }
      this.parts = [];
      this.length = 0;
      this.drain = false;
      start = lf + 1;
    }
  }
}

// M and N are private WebSocket channel tags, removed before delivery. Each
// Unix socket still has the standard Omnivox stdin/stdout interface.
function wireEndpoint(directory, session, send, control, fail) {
  const writers = new Map();
  const barriers = new Set();
  let closed = false, serial = 0;
  function record(lane, line) {
    if (closed) return;
    if (!line.startsWith('iphone_event ')) return send(lane + ' ' + line);
    let packet;
    try { packet = JSON.parse(line.slice(13)); } catch { return; }
    if (packet?.type === 'reset-done') {
      if (serial && packet.id === serial) {
        barriers.add(lane);
        if (barriers.size === 2) { serial = 0; control(packet); }
      }
    } else if (lane === 'M') control(packet);
  }
  const servers = ['M', 'N'].map(lane => {
    const server = net.createServer(socket => {
      if (closed || writers.has(lane)) return socket.destroy();
      writers.set(lane, socket);
      const records = new Records(line => record(lane, line));
      socket.on('data', bytes => records.write(bytes));
      socket.on('error', () => socket.destroy());
      socket.on('close', () => { if (!closed) fail(); });
    });
    server.on('error', fail);
    return server;
  });
  const listening = Promise.all(servers.map(server => once(server, 'listening')));
  for (const [i, suffix] of ['.sock', '.n'].entries()) servers[i].listen(path.join(directory, session + suffix));
  return {
    listening,
    reset(id) { serial = id; barriers.clear(); },
    reply(message) {
      const writer = writers.get(message[0]);
      const line = message.slice(2);
      // Only public worker events belong on stdout. A handset cannot inject
      // private launcher/library events or additional records into Emacs.
      if (!writer || message[1] !== ' ' || /[\r\n]/.test(line) || Buffer.byteLength(line) > recordLimit ||
          !/^__(?:OMNIVOX_CONTROL|EMACSVOX_TRACKED|EMACSVOX_MARKER)__ /.test(line) ||
          writer.writableLength > recordLimit * 2) return false;
      writer.write(line + '\n');
      return true;
    },
    close() {
      closed = true;
      for (const writer of writers.values()) writer.destroy();
      for (const server of servers) server.close();
    },
  };
}

module.exports = {wireEndpoint, recordLimit, Records};
