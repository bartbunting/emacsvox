// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later

const net = require('node:net');
const http = require('node:http');
const path = require('node:path');
const { WebSocketServer, WebSocket } = require('ws');
const { attachTerminal, openPhoneFrame } = require('./terminal.cjs');

const maxBytes = 512 * 1024;
const openObject = {type: 'cue', name: 'open-object'};
const resource = path.resolve(__dirname, '../../sounds/packs/accent/open-object.ogg');
// Emacsvox escapes dollar signs and opening brackets in quoted Tcl paths.
const openObjectPaths = new Set([resource, JSON.stringify(resource).replace(/[$[]/g, '\\$&')]);

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

  queue(item) {
    if (typeof item === 'string') this.bytes += Buffer.byteLength(item);
    if (this.bytes > maxBytes || this.parts.length >= 4096) this.abandoned = true;
    if (!this.abandoned) this.parts.push(item);
  }

  dispatch() {
    let words = [];
    const flushWords = () => {
      if (words.length) this.send({type: 'speak', text: words.join(' ')});
      words = [];
    };
    if (!this.abandoned) {
      for (const item of this.parts) {
        if (item === openObject) {
          flushWords();
          this.send(openObject);
        } else {
          words.push(item);
        }
      }
      flushWords();
    }
    this.clear();
  }

  record(line) {
    const match = /^(\w+)(?:\s+(.*))?$/u.exec(line);
    if (!match) return;
    const [, command, argument = ''] = match;
    const value = argument.startsWith('{') && argument.endsWith('}')
      ? argument.slice(1, -1) : argument;
    switch (command) {
      case 'q':
        this.queue(value);
        break;
      case 'a':
        if (openObjectPaths.has(value)) this.queue(openObject);
        break;
      case 'p':
        if (openObjectPaths.has(value)) this.send({...openObject, immediate: true});
        break;
      case 'd':
        this.dispatch();
        break;
      case 's':
      case 'tts_reset':
        this.clear();
        this.send({ type: 'stop' });
        break;
      case 'l':
      case 'tts_say':
        this.send({ type: 'stop', scope: 'speech' });
        if (value) this.send({ type: command === 'l' ? 'letter' : 'speak', text: value });
        break;
    }
  }
}

function createRelay(host, peer, {port = 8787, metroPort = 8788, terminalSocket, sharedDirectory} = {}) {
  let phone, producer, input, terminal;
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
      '<a href="exp://' + host + ':' + metroPort + '">Open receiver in Expo Go</a></main>');
  });
  const wss = new WebSocketServer({ noServer: true, maxPayload: terminalSocket ? 2048 : 256, perMessageDeflate: false });
  httpServer.on('upgrade', (req, socket, head) => {
    // The native iOS WebSocket may supply its own endpoint as Origin.
    const origin = req.headers.origin;
    if (req.socket.remoteAddress !== peer || req.url !== '/speech' ||
        (origin && origin !== 'http://' + host + ':' + port)) return socket.destroy();
    wss.handleUpgrade(req, socket, head, ws => {
      const previous = phone;
      terminal?.close();
      terminal = undefined;
      phone = ws;
      previous?.terminate();
      input?.invalidate();
      let lastSeen = Date.now(), readyId = 0;
      const timer = setInterval(() => {
        if (Date.now() - lastSeen > 12000) ws.terminate();
      }, 3000);
      ws.on('error', () => ws.terminate());
      ws.on('close', () => {
        clearInterval(timer);
        if (phone !== ws) return;
        terminal?.close();
        terminal = undefined;
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
          readyId = Number(command.slice(6));
          if (!sharedDirectory || terminal) send({ type: 'ready', id: readyId });
        } else if (terminal && command.startsWith('key ') && command.length > 4) {
          void terminal.write(command.slice(4));
        } else ws.terminate();
      });
      function connected(session) {
        const attached = terminalSocket && attachTerminal(terminalSocket, send, () => ws.terminate(), session);
        if (phone !== ws || ws.readyState !== WebSocket.OPEN) return attached?.close();
        terminal = attached;
        send({ type: 'ready', id: readyId, ...(terminalSocket && {keyboard: true}) });
      }
      if (sharedDirectory) openPhoneFrame(terminalSocket, sharedDirectory).then(connected, () => ws.terminate());
      else connected();
    });
  });
  return { backend, httpServer };
}

module.exports = { createRelay, LegacyInput };

if (require.main === module) {
  const [host, peer, socketPath, terminalSocket, sharedDirectory] = process.argv.slice(2);
  const port = sharedDirectory ? 8794 : terminalSocket ? 8791 : 8787;
  const relay = createRelay(host, peer, {port, metroPort: port + 1, terminalSocket, sharedDirectory});
  const listen = () => relay.httpServer.listen(port, host, () =>
    console.log('On your iPhone, open http://' + host + ':' + port + ' in Safari.'));
  // The keyboard launcher signals after the isolated Emacs reaches its command loop.
  if (terminalSocket) process.once('SIGUSR2', listen);
  else listen();
  relay.backend.listen(socketPath);
}
