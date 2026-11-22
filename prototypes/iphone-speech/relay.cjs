// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later

const net = require('node:net');
const http = require('node:http');
const { WebSocketServer, WebSocket } = require('ws');

const maxBytes = 512 * 1024;

// One instance per Emacs stdio producer. A receiver change invalidates even
// the tail of a partially received UTF-8 record or undispatched batch.
class LegacyInput {
  constructor(send) {
    this.send = send;
    this.tail = Buffer.alloc(0);
    this.skipLine = false;
    this.clear();
  }

  clear() {
    this.parts = [];
    this.bytes = 0;
    this.abandoned = false;
  }

  invalidate() {
    this.abandoned ||= this.parts.length > 0 || this.tail.length > 0;
    this.parts = [];
    this.bytes = 0;
    this.skipLine ||= this.tail.length > 0;
    this.tail = Buffer.alloc(0);
  }

  write(chunk) {
    let start = 0;
    while (start < chunk.length) {
      const end = chunk.indexOf(10, start);
      const part = chunk.subarray(start, end < 0 ? chunk.length : end);
      if (this.tail.length + part.length > maxBytes) {
        this.abandoned = true;
        this.skipLine = true;
      }
      if (!this.skipLine) this.tail = Buffer.concat([this.tail, part]);
      if (end < 0) break;
      if (!this.skipLine) this.record(this.tail.toString('utf8').trim());
      this.tail = Buffer.alloc(0);
      this.skipLine = false;
      start = end + 1;
    }
  }

  record(line) {
    const match = /^(\w+)(?:\s+(.*))?$/u.exec(line);
    if (!match) return;
    const [, command, argument = ''] = match;
    const value = argument.startsWith('{') && argument.endsWith('}')
      ? argument.slice(1, -1) : argument;
    switch (command) {
      case 'q':
        this.bytes += Buffer.byteLength(value);
        if (this.bytes > maxBytes || this.parts.length >= 4096) this.abandoned = true;
        if (!this.abandoned) this.parts.push(value);
        break;
      case 'd':
        if (!this.abandoned && this.parts.length) {
          this.send({ type: 'speak', text: this.parts.join(' ') });
        }
        this.clear();
        break;
      case 's':
      case 'tts_reset':
        this.clear();
        this.send({ type: 'stop' });
        break;
      case 'l':
      case 'tts_say':
        this.send({ type: 'stop' });
        if (value) this.send({ type: command === 'l' ? 'letter' : 'speak', text: value });
        break;
    }
  }
}

function createRelay(host, peer) {
  let phone, producer, input;
  const send = message => {
    if (phone?.readyState !== WebSocket.OPEN) return;
    if (phone.bufferedAmount > maxBytes) return phone.terminate();
    phone.send(JSON.stringify(message));
  };
  const backend = net.createServer(socket => {
    if (producer) return socket.destroy();
    producer = socket;
    input = new LegacyInput(send);
    socket.on('data', chunk => input.write(chunk));
    socket.on('error', () => socket.destroy());
    socket.on('close', () => {
      producer = input = undefined;
      send({ type: 'stop' });
    });
  });
  const httpServer = http.createServer((req, res) => {
    if (req.socket.remoteAddress !== peer || req.url !== '/') {
      res.writeHead(403).end();
      return;
    }
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
    res.end('<title>Emacsvox Speech</title><main><h1>Emacsvox Speech</h1>' +
      '<a href="exp://' + host + ':8788">Open receiver in Expo Go</a></main>');
  });
  const wss = new WebSocketServer({ noServer: true, maxPayload: 256, perMessageDeflate: false });
  httpServer.on('upgrade', (req, socket, head) => {
    // The native iOS WebSocket may supply its own endpoint as Origin.
    const origin = req.headers.origin;
    if (req.socket.remoteAddress !== peer || req.url !== '/speech' ||
        (origin && origin !== 'http://' + host + ':8787')) return socket.destroy();
    wss.handleUpgrade(req, socket, head, ws => {
      const previous = phone;
      phone = ws;
      previous?.terminate();
      input?.invalidate();
      let lastSeen = Date.now();
      const timer = setInterval(() => {
        if (Date.now() - lastSeen > 12000) ws.terminate();
      }, 3000);
      ws.on('error', () => ws.terminate());
      ws.on('close', () => {
        clearInterval(timer);
        if (phone !== ws) return;
        input?.invalidate();
        phone = undefined;
      });
      ws.on('message', (data, binary) => {
        if (phone !== ws || binary) return ws.terminate();
        lastSeen = Date.now();
        const command = data.toString();
        if (command === 'ping') send({ type: 'pong' });
        else if (/^reset [0-9]{1,12}$/.test(command)) {
          input?.invalidate();
          send({ type: 'ready', id: Number(command.slice(6)) });
        } else ws.terminate();
      });
      send({ type: 'ready', id: 0 });
    });
  });
  return { backend, httpServer };
}

module.exports = { createRelay, LegacyInput };

if (require.main === module) {
  const [host, peer, socketPath] = process.argv.slice(2);
  const relay = createRelay(host, peer);
  relay.backend.listen(socketPath);
  relay.httpServer.listen(8787, host, () =>
    console.log('On your iPhone, open http://' + host + ':8787 in Safari.'));
}
