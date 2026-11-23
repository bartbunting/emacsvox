// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

struct WireItem: Decodable {
  enum Kind: String, Decodable { case speech, tone, silence, sound }
  enum Placement: String, Decodable { case independent, insert, overlay }
  let kind: Kind
  var placement: Placement?
  var text: String?, voice: String?, rate: Float?, pitch: Float?, gain: Float?
  var path: String?, hz: Float?, ms: UInt32?
  var marks: [WireToneMark]?
  var anchors: [WireAnchor]?
  var startMarker: String?
}

struct WireToneMark: Decodable {
  let offset: Int
  let placement: WireItem.Placement
  let hz: Float, ms: UInt32, gain: Float
  var after: Bool?
}

struct WireReceipts: Decodable {
  let completed: String, failed: String, cancelled: String
}

struct WireAction: Decodable {
  enum Op: String, Decodable { case reply, batch, immediate, timeline, stop, exit }
  let op: Op
  var key: String?, bytes: Int?, interrupt: Bool?
  var line: String?, items: [WireItem]?, item: WireItem?, receipts: WireReceipts?
}

protocol WireOutput: AnyObject {
  // Each callback runs once on the owning queue, after playback or failure.
  func play(_ item: WireItem, done: @escaping (Bool) -> Void)
  // An overlay can continue after the next speech starts. Its ticket keeps
  // tracked dispatch open until the actual last sample plays.
  func playMixed(_ items: ArraySlice<WireItem>, reached: @escaping (String) -> Void, holdTail: @escaping () -> () -> Void,
                 done: @escaping (Int, Bool) -> Void)
  func playTimeline(_ plan: WirePresentation, holdTail: @escaping () -> () -> Void, done: @escaping (Bool) -> Void)
  func stop(all: Bool)
}

private final class WireBatch {
  let items: [WireItem], receipts: WireReceipts?, bytes: Int
  var presentation: WirePresentation?
  var timelineStarted = false
  let done: ((Bool) -> Void)?
  var index = 0, separateUntil = 0, outstanding = 0, failed = false, finished = false
  init(_ items: [WireItem], _ receipts: WireReceipts?, _ bytes: Int, _ done: ((Bool) -> Void)?) {
    self.done = done
    self.items = items
    self.receipts = receipts
    self.bytes = bytes
  }

  func mixedRun() -> ArraySlice<WireItem>? {
    guard index >= separateUntil else { return nil }
    var end = index, speech = false
    while end < items.count {
      let item = items[end]
      let inlineTone = item.kind == .tone && (item.placement == .insert || item.placement == .overlay)
      if item.kind == .speech, let text = item.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        speech = true
      } else if !inlineTone { break }
      end += 1
    }
    // Letters and unmarked speech use the same PCM output level as a spoken line.
    if speech { return items[index..<end] }
    separateUntil = end
    return nil
  }
}

// One scheduler per worker. Speech and silence share a clock. Sound has a FIFO
// of its own and a queued icon starts when preceding speech reaches its boundary.
final class WireSchedule {
  private let output: WireOutput, reply: (String) -> Void
  private var waiting: [WireBatch] = [], live: [ObjectIdentifier: WireBatch] = [:]
  private var bytes = 0, blocked = false, advancing = false

  init(_ output: WireOutput, reply: @escaping (String) -> Void) {
    self.output = output
    self.reply = reply
  }

  func submit(_ action: WireAction, bytes size: Int, presentation: WirePresentation? = nil) {
    switch action.op {
    case .reply: if let line = action.line { reply(line) }
    case .stop, .exit: stop(all: true)
    case .immediate:
      guard let item = action.item else { return }
      if item.kind == .speech { stop(all: false) }
      admit([item], nil, size, immediate: item.kind == .sound)
    case .timeline:
      guard let presentation, let receipts = action.receipts, let bytes = action.bytes else { return }
      if action.interrupt == true {
        guard (0...32 * 1024 * 1024).contains(bytes) else { reply(receipts.failed); return }
        stop(all: false)
      }
      admit([], receipts, bytes, immediate: false, presentation: presentation)
    case .batch: admit(action.items ?? [], action.receipts, size, immediate: false)
    }
  }

  func diagnosticEffect(_ item: WireItem, done: @escaping (Bool) -> Void) {
    admit([item], nil, 0, immediate: true, done: done)
  }

  func permission(_ item: WireItem, done: @escaping (Bool) -> Void) {
    stop(all: false)
    admit([item], nil, item.text?.utf8.count ?? 0, immediate: false, done: done)
  }

  private func admit(_ items: [WireItem], _ receipts: WireReceipts?, _ size: Int, immediate: Bool, presentation: WirePresentation? = nil, done: ((Bool) -> Void)? = nil) {
    var replaced = presentation?.key.map { key in live.values.filter { $0.presentation?.key == key } } ?? []
    var freed = replaced.reduce(0) { $0 + $1.bytes }
    func fits() -> Bool {
      live.count - replaced.count < 33 && size >= 0 && size <= 32 * 1024 * 1024 - bytes + freed
    }
    if !fits(), size <= 32 * 1024 * 1024 {
      for queued in waiting where !queued.timelineStarted && queued.presentation?.key != nil {
        if replaced.contains(where: { $0 === queued }) { continue }
        replaced.append(queued)
        freed += queued.bytes
        if fits() { break }
      }
    }
    guard fits() else {
      done?(false)
      if let receipts { reply(receipts.failed) }
      return
    }
    let job = WireBatch(items, receipts, size, done)
    job.presentation = presentation
    for old in replaced {
      old.finished = true
      if waiting.first === old && old.timelineStarted { blocked = false }
      waiting.removeAll { $0 === old }
      live.removeValue(forKey: ObjectIdentifier(old))
      bytes -= old.bytes
      old.presentation?.cancel(replacing: true)
      if let receipts = old.receipts { reply(receipts.cancelled) }
    }
    live[ObjectIdentifier(job)] = job
    bytes += size
    if immediate {
      job.index = job.items.count
      start(items[0], job, clock: false)
      finishIfPlayed(job)
    } else {
      waiting.append(job)
      // Independent tones start at dispatch, including tones following speech.
      for tone in items where tone.kind == .tone && tone.placement == .independent { start(tone, job, clock: false) }
      advance()
    }
  }

  func stop(all: Bool) {
    let cancelled = Array(live.values)
    waiting.removeAll()
    live.removeAll()
    bytes = 0
    blocked = false
    for job in cancelled { job.finished = true; job.presentation?.cancel() }
    output.stop(all: all)
    for job in cancelled {
      job.done?(false)
      if let receipts = job.receipts { reply(receipts.cancelled) }
    }
  }

  private func advance() {
    guard !advancing else { return }
    advancing = true
    defer { advancing = false }
    while !blocked, let job = waiting.first {
      if let plan = job.presentation, !job.timelineStarted {
        job.timelineStarted = true
        job.outstanding += 1
        blocked = true
        output.playTimeline(plan, holdTail: { [weak self, weak job] in
          guard let job, !job.finished else { return {} }
          job.outstanding += 1
          return { [weak self, weak job] in
            guard let job, !job.finished else { return }
            job.outstanding -= 1
            self?.finishIfPlayed(job)
          }
        }) { [weak self, weak job] ok in
          guard let self, let job, !job.finished else { return }
          job.failed = !ok
          job.outstanding -= 1
          self.blocked = false
          self.finishIfPlayed(job)
          self.advance()
        }
        continue
      }
      if job.index == job.items.count {
        waiting.removeFirst()
        finishIfPlayed(job)
        continue
      }
      if let run = job.mixedRun() {
        blocked = true
        job.separateUntil = run.endIndex
        output.playMixed(run, reached: { [weak self, weak job] marker in
          guard let job, !job.finished else { return }
          self?.reply(marker)
        }, holdTail: { [weak self, weak job] in
          guard let job, !job.finished else { return {} }
          job.outstanding += 1
          return { [weak self, weak job] in
            guard let job, !job.finished else { return }
            job.outstanding -= 1
            self?.finishIfPlayed(job)
          }
        }) { [weak self, weak job] played, ok in
          guard let self, let job, !job.finished else { return }
          let lostMarker = run.dropFirst(played).contains { $0.startMarker != nil }
          job.failed = job.failed || !ok || lostMarker
          job.index = lostMarker ? run.endIndex : run.startIndex + played
          self.blocked = false
          self.advance()
        }
        continue
      }
      let item = job.items[job.index]
      job.index += 1
      if item.kind == .tone && item.placement == .independent { continue }
      let clock = item.kind == .speech || item.kind == .silence || item.placement == .insert
      blocked = clock
      start(item, job, clock: clock)
    }
  }

  private func start(_ item: WireItem, _ job: WireBatch, clock: Bool) {
    job.outstanding += 1
    output.play(item) { [weak self, weak job] ok in
      guard let self, let job, !job.finished else { return }
      job.failed = job.failed || !ok
      job.outstanding -= 1
      if clock { self.blocked = false }
      self.finishIfPlayed(job)
      if clock { self.advance() }
    }
  }

  private func finishIfPlayed(_ job: WireBatch) {
    guard !job.finished, job.index == job.items.count, job.outstanding == 0 else { return }
    job.finished = true
    bytes -= job.bytes
    live.removeValue(forKey: ObjectIdentifier(job))
    job.done?(!job.failed)
    if let receipts = job.receipts { reply(job.failed ? receipts.failed : receipts.completed) }
  }
}
