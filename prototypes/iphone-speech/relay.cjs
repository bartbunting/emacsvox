// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later

const net = require('node:net');
const { randomUUID } = require('node:crypto');
const { once } = require('node:events');
const http = require('node:http');
const path = require('node:path');
const { WebSocketServer, WebSocket } = require('ws');
const { attachTerminal, openPhoneFrame, frameControl, sshOffer } = require('./terminal.cjs');

const maxBytes = 512 * 1024;
const openObject = {type: 'cue', name: 'open-object'};
const resource = path.resolve(__dirname, '../../sounds/packs/accent/open-object.ogg');
// Emacsvox escapes dollar signs and opening brackets in quoted Tcl paths.
const openObjectPaths = new Set([resource, JSON.stringify(resource).replace(/[$[]/g, '\\$&'),
  'omnivox-icon:packs/accent/open-object.ogg', '"omnivox-icon:packs/accent/open-object.ogg"']);

// One instance per Emacs stdio producer. A receiver change invalidates even
// the tail of a partially received UTF-8 record or undispatched batch.
class LegacyInput {
  constructor(send, control, phoneAudio = false) {
    this.phoneAudio = phoneAudio;
    this.control = control;
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
      if (words.length) this.voice('speak', words.join(' '));
      words = [];
    };
    if (!this.abandoned) {
      for (const item of this.parts) {
        if (typeof item !== 'string') {
          flushWords();
          this.send(item);
        } else {
          words.push(item);
        }
      }
      flushWords();
    }
    this.clear();
  }

  voice(type, text) {
    this.send({type, text, ...(this.rate !== undefined && {rate: this.rate})});
  }

  setRate(raw) {
    if (raw === undefined || raw.trim() === '' || !Number.isFinite(Number(raw))) return;
    const n = Number(raw);
    this.rate = Math.max(0, Math.min(2, n > 1 ? n / 100 : n));
  }

  record(line) {
    if (this.control && line.startsWith('iphone_event ')) {
      try { this.control(JSON.parse(line.slice(13))); } catch { /* Drop malformed control records. */ }
      return;
    }
    const match = /^(\w+)(?:\s+(.*))?$/u.exec(line);
    if (!match) return;
    const [, command, argument = ''] = match;
    const value = argument.startsWith('{') && argument.endsWith('}')
      ? argument.slice(1, -1) : argument;
    switch (command) {
      case 'q':
        this.queue(value);
        break;
      case 'tts_sync_state':
        if (this.phoneAudio) this.setRate(value.split(/\s+/)[3]);
        break;
      case 'tts_set_speech_rate':
        if (this.phoneAudio) this.setRate(value);
        break;
      case 't': {
        if (!this.phoneAudio) break;
        const args = value.trim().split(/\s+/);
        const [hz, ms] = args.map(Number);
        if (args.length === 2 && Number.isFinite(hz) && hz > 0 && hz <= 24000 &&
            Number.isInteger(ms) && ms > 0 && ms <= 60000) this.queue({type: 'tone', hz, ms});
        break;
      }
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
        if (value) this.voice(command === 'l' ? 'letter' : 'speak', value);
        break;
    }
  }
}

// A new terminal gets a private Unix socket. Late bytes and an old producer's
// EOF belong to that WebSocket even while its replacement is attaching.
function frameSpeech(directory, session, send, control, fail) {
  let writer;
  const input = new LegacyInput(send, control, true);
  const server = net.createServer(socket => {
    if (writer) return socket.destroy();
    writer = socket;
    socket.on('data', bytes => input.write(bytes));
    socket.on('error', () => socket.destroy());
    socket.on('close', () => send({type: 'stop'}));
  });
  server.on('error', fail);
  const listening = once(server, 'listening');
  server.listen(path.join(directory, session + '.sock'));
  return {listening, input, close() {
    writer?.destroy();
    server.close();
  }};
}

function createRelay(host, peer, {port = 8787, metroPort = 8788, terminalSocket, sharedDirectory, routed = false, sshOnly = false} = {}) {
  let phone, producer, input, terminal;
  const send = message => {
    if (phone?.readyState !== WebSocket.OPEN) return;
    if (phone.bufferedAmount > maxBytes) return phone.terminate();
    phone.send(JSON.stringify(message));
  };
  const backend = net.createServer(socket => {
    if (routed || producer) return socket.destroy();
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
    if (sshOnly || req.socket.remoteAddress !== peer || req.url !== '/') {
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
    const ssh = routed && req.url === '/speech/ssh';
    if (req.socket.remoteAddress !== peer || (!ssh && (sshOnly || req.url !== '/speech')) ||
        (origin && origin !== 'http://' + host + ':' + port)) return socket.destroy();
    wss.handleUpgrade(req, socket, head, ws => {
      const previous = phone;
      terminal?.close();
      terminal = undefined;
      phone = ws;
      previous?.terminate();
      input?.invalidate();
      const session = sharedDirectory && 'phone-' + randomUUID();
      let lastSeen = Date.now(), readyId = 0, attached = false;
      const control = (action, serial = 0) =>
        frameControl(sharedDirectory, session, action, serial).catch(() => ws.terminate());
      const receiveControl = packet => {
        if (phone !== ws || !packet) return;
        if (packet.type === 'attached' && packet.id === session && ssh && !attached) connected();
        else if (packet.type === 'stop-all') send({type: 'stop', scope: 'all'});
        else if (packet.type === 'reset-done' && packet.id === readyId && attached) send({type: 'ready', id: readyId});
        else if (attached && ['permission', 'resolved'].includes(packet.type) &&
                 typeof packet.id === 'string') send(packet);
      };
      const endpoint = routed && frameSpeech(sharedDirectory, session,
        packet => { if (phone === ws) send(packet); }, receiveControl, () => ws.terminate());
      const timer = setInterval(() => {
        if (Date.now() - lastSeen > 12000) ws.terminate();
      }, 3000);
      ws.on('error', () => ws.terminate());
      ws.on('close', () => {
        clearInterval(timer);
        if (ssh && attached) void frameControl(sharedDirectory, session, 'detach', 0).catch(() => {});
        if (endpoint) endpoint.close();
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
          if (endpoint) endpoint.input.invalidate();
          readyId = Number(command.slice(6));
          if (routed && attached) void control('stop', readyId);
          else if (!sharedDirectory || terminal) send({ type: 'ready', id: readyId });
        } else if (terminal && command.startsWith('key ') && command.length > 4) {
          void terminal.write(command.slice(4));
        } else ws.terminate();
      });
      function connected(terminalSession) {
        const pane = !ssh && terminalSocket && attachTerminal(terminalSocket,
          packet => { if (phone === ws) send(packet); }, () => ws.terminate(), terminalSession);
        if (phone !== ws || ws.readyState !== WebSocket.OPEN) { if (pane) pane.close(); return; }
        terminal = pane || undefined;
        attached = true;
        send({ type: 'ready', id: readyId, ...(pane && {keyboard: true}) });
        if (routed) void control('sync');
      }
      if (sharedDirectory) Promise.resolve(endpoint && endpoint.listening).then(() => {
        if (phone !== ws || ws.readyState !== WebSocket.OPEN) return;
        if (ssh) return sshOffer(sharedDirectory, session).then(packet => { if (phone === ws) send(packet); });
        return openPhoneFrame(terminalSocket, sharedDirectory, session).then(connected);
      }).catch(() => ws.terminate());
      else connected();
    });
  });
  return { backend, httpServer };
}

module.exports = { createRelay, LegacyInput };

if (require.main === module) {
  const [host, peer, socketPath, terminalSocket, sharedDirectory, mode] = process.argv.slice(2);
  const sshOnly = mode === '--ssh-only';
  const routed = sshOnly || mode === '--routed';
  const port = routed ? 8797 : sharedDirectory ? 8794 : terminalSocket ? 8791 : 8787;
  const relay = createRelay(host, peer, {port, metroPort: port + 1, terminalSocket, sharedDirectory, routed, sshOnly});
  const listen = () => relay.httpServer.listen(port, host, () =>
    console.log(sshOnly ? 'Ready for the signed SSH app.' : 'On your iPhone, open http://' + host + ':' + port + ' in Safari.'));
  // The keyboard launcher signals after the isolated Emacs reaches its command loop.
  if (terminalSocket) process.once('SIGUSR2', listen);
  else listen();
  relay.backend.listen(socketPath);
}
