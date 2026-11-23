// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import OmnivoxMobile

// Drive the production scheduler with explicit Apple synthesis and hardware
// completion callbacks. Rust's sample comparisons run in the paired crate.
func checkMixedPlayback(_ root: String, voices: String) throws {
  let firstMark = WireToneMark(offset: 0, placement: .insert, hz: 440, ms: 20, gain: 1)
  let innerMark = WireToneMark(offset: 5, placement: .insert, hz: 440, ms: 20, gain: 1)
  var word = WireItem(kind: .speech, text: "CaféCase & <x>", rate: 1.5, marks: [firstMark, innerMark])
  var bookmarks = WireBookmarks(word)!
  precondition(bookmarks.ssml.contains("Café<mark name=\"ov-5\"/>Case &amp; &lt;x&gt;"))
  precondition(bookmarks.ssml.contains("rate=\"150%\""))
  bookmarks.observe("ov-0", byte: 0)
  bookmarks.observe("ov-5", byte: 360)
  bookmarks.observe(WireBookmarks.end, byte: 800)
  precondition(bookmarks.complete && bookmarks.nativeFrames(bytesPerFrame: 2, totalFrames: 400) == [0, 180])
  bookmarks.observe("ov-5", byte: 400)
  precondition(bookmarks.nativeFrames(bytesPerFrame: 2, totalFrames: 400) == [0, nil])
  word.marks = [WireToneMark(offset: 4, placement: .insert, hz: 440, ms: 20, gain: 1)]
  precondition(WireBookmarks(word) == nil)
  let clock = ov_ios_mix_new()!, token = ov_ios_token_new()!
  defer { ov_ios_mix_free(clock); ov_ios_token_free(token) }
  var mark = OvToneMark(frame: 180, hz: 440, ms: 20, gain: 1, insert: true)
  let samples = [Float](repeating: 0.25, count: 400)
  let pcm = samples.withUnsafeBufferPointer { ov_ios_mix_marked(clock, $0.baseAddress, $0.count, 44100, 1, &mark, 1, token) }!
  precondition(ov_ios_frames(pcm) == 1282)
  let words = ov_ios_samples(pcm)!
  precondition(words[359] == 0.25 && words[360] == 0 && words[(180 + 882) * 2] == 0.25)
  ov_ios_pcm_free(pcm)
  typealias Run = WirePlayback<Int>
  let output = TestOutput(root)
  var replies: [String] = []
  let lane = WireLane(output) { replies.append($0) }
  precondition(lane.setVoices(voices, preferred: "test-1"))
  var active: Run?, cues: [[WireItem]] = [], ready: ((Run.Packet) -> Void)?, end: ((Bool) -> Void)?
  var queued: [Int] = [], played: [() -> Void] = [], tail = false
  output.mixed = { items, holdTail, done in
    let run = Run(items, speech: { tones, _, audio, finished in
      cues.append(tones)
      ready = audio
      end = finished
    }, flush: { _, flushed in flushed(nil, tail ? (99, 88) : nil, true) },
    enqueue: { buffer, finished in queued.append(buffer); played.append(finished) },
    holdTail: holdTail, done: done, release: { active = nil })
    active = run
    run.advance()
  }
  output.stopMixed = { active?.stop(); active = nil }
  func send(_ records: [String]) throws { for line in records { try lane.feed(line, muted: false) } }
  func voice(_ id: Int) { ready?((id, 1024)); end?(true) }
  tail = true
  try send(["q First", "emacsvox_tone 1 insert 440 20", "q Second", "emacsvox_tone 1 overlay 250 130",
            "q third", "emacsvox_tracked_dispatch 120", "q following", "d"])
  precondition(cues.count == 1 && cues[0].isEmpty && queued.isEmpty)
  voice(1)
  precondition(cues.count == 2 && cues[1].first?.placement == .insert && cues[1].first?.ms == 20)
  voice(2)
  precondition(cues.count == 3 && cues[2].first?.placement == .overlay && cues[2].first?.ms == 130)
  voice(3)
  precondition(queued == [1, 2, 3, 99] && output.started.isEmpty)
  for i in 0..<3 { played[i]() }
  precondition(output.started == [.speech] && replies.isEmpty)
  played[3]()
  precondition(replies == ["__EMACSVOX_TRACKED__ 120 completed"])

  // An unavailable voice retries only the unheard suffix, including its tone.
  tail = false
  played.removeAll()
  output.started.removeAll()
  try send(["q first", "emacsvox_tone 1 insert 440 20", "q second", "emacsvox_tracked_dispatch 121"])
  voice(4)
  end?(false)
  precondition(output.started.isEmpty)
  played[0]()
  precondition(output.started == [.tone, .speech] && replies.last == "__EMACSVOX_TRACKED__ 121 completed")

  try send(["emacsvox_tone 1 insert 440 20", "q old", "emacsvox_tracked_dispatch 122"])
  let stale = ready
  try send(["s", "q fresh", "d"])
  let count = queued.count
  stale?((5, 1024))
  precondition(queued.count == count && replies.last == "__EMACSVOX_TRACKED__ 122 cancelled")
  print("Passed mixed PCM lookahead, independent tail completion, unheard voice fallback and Stop.")
}
