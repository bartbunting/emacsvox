// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

// The driver supplies PCM from the Omnivox mixer. Its callbacks and all
// playback bookkeeping run on the owning lane. One speech request is prepared
// at a time, with up to one second queued before starting the next voice.
final class WirePlayback<Buffer> {
  typealias Packet = (buffer: Buffer, frames: Int)
  typealias Speech = ([WireItem], WireItem, @escaping (Packet) -> Void, @escaping (Bool) -> Void) -> Void
  typealias Flush = ([WireItem]?, @escaping (Packet?, Packet?, Bool) -> Void) -> Void
  private let items: [WireItem], speech: Speech, flush: Flush
  private let enqueue: (Buffer, @escaping () -> Void) -> Void
  private let holdTail: () -> () -> Void, done: (Int, Bool) -> Void, release: () -> Void
  private var consumed = 0, queued = 0, reading = false, finishing = false, flushed = false
  private var ok = true, stopped = false, primaryDone = false, tailPlaying = false

  init(_ items: ArraySlice<WireItem>, speech: @escaping Speech, flush: @escaping Flush,
       enqueue: @escaping (Buffer, @escaping () -> Void) -> Void, holdTail: @escaping () -> () -> Void,
       done: @escaping (Int, Bool) -> Void, release: @escaping () -> Void) {
    self.items = Array(items)
    self.speech = speech
    self.flush = flush
    self.enqueue = enqueue
    self.holdTail = holdTail
    self.done = done
    self.release = release
  }

  func stop() { stopped = true }

  func advance() {
    guard !stopped, !reading else { return }
    if finishing {
      if flushed && queued == 0 && !primaryDone {
        primaryDone = true
        done(consumed, ok)
      }
      if primaryDone && !tailPlaying && !stopped { stopped = true; release() }
      return
    }
    guard queued < 44100 else { return }
    let next = items[consumed...].firstIndex { $0.kind == .speech } ?? items.count
    let cues = Array(items[consumed..<next])
    guard next < items.count else { finish(cues); return }
    reading = true
    speech(cues, items[next], { [weak self] packet in
      guard let self, self.reading, !self.stopped else { return }
      self.consumed = next + 1
      self.schedule(packet)
    }, { [weak self] delivered in
      guard let self, self.reading, !self.stopped else { return }
      self.reading = false
      if delivered && self.consumed == next + 1 {
        self.advance()
      } else {
        // Replay an untouched suffix with the system voice. If samples already
        // escaped, report failure and leave that fragment heard only once.
        self.ok = self.consumed != next + 1
        self.finish(nil)
      }
    })
  }

  private func schedule(_ packet: Packet) {
    queued += packet.frames
    enqueue(packet.buffer) { [weak self] in
      guard let self, !self.stopped else { return }
      self.queued -= packet.frames
      self.advance()
    }
  }

  private func finish(_ pending: [WireItem]?) {
    finishing = true
    flush(pending) { [weak self] primary, tail, valid in
      guard let self, !self.stopped else { return }
      self.ok = self.ok && valid
      if valid, pending != nil { self.consumed = self.items.count }
      if let primary { self.schedule(primary) }
      if let tail {
        self.tailPlaying = true
        let played = self.holdTail()
        self.enqueue(tail.buffer) { [weak self] in
          guard let self, !self.stopped else { return }
          self.tailPlaying = false
          played()
          self.advance()
        }
      }
      self.flushed = true
      self.advance()
    }
  }
}
