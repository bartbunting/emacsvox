// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import OmnivoxMobile

// Match the five cue offsets from the handset. Give Apple no bookmarks and
// deliberately uneven phrase durations. Compare the whole Rust output to PCM.
func checkMissingWordTiming(_ root: String, voices: String, envelope: Data) throws {
  let offsets = [0, 5, 10, 15, 19], parts = ["Lime ", "Plum ", "Pear ", "Fig ", "Café"]
  let lengths = [319, 971, 453, 617, 287]
  var document = try JSONSerialization.jsonObject(with: envelope) as! [String: Any]
  var spans = document["spans"] as! [[String: Any]]
  spans[0]["text"] = parts.joined()
  document["spans"] = spans
  let pair = Array((document["actions"] as! [[String: Any]]).prefix(2))
  document["actions"] = offsets.flatMap { offset in
    pair.enumerated().map { i, prototype -> [String: Any] in
      var action = prototype, position = action["position"] as! [String: Any]
      position["utf8_offset"] = offset
      action["id"] = (i == 0 ? "tone." : "capital.") + String(offset)
      action["position"] = position
      return action
    }
  }
  let output = TestOutput(root), lane = WireLane(output) { _ in }
  precondition(lane.setVoices(voices, preferred: "test-1"))
  try lane.feed("tts_split_caps 0", muted: false)
  let record = "emacsvox_timeline " + (try JSONSerialization.data(withJSONObject: document)).base64EncodedString()
  let accepted = Array(record.utf8).withUnsafeBufferPointer { ov_ios_record(lane.worker, $0.baseAddress, $0.count) }!
  ov_ios_string_free(accepted)
  let presentation = WirePresentation(ov_ios_take_presentation(lane.worker)!, key: nil, reply: { _ in })
  let items = presentation.prepare(bundle: output.loader, personal: nil)!
  precondition(items.count == 1)
  let item = items[0], plan = WireBookmarks(item)!
  precondition(plan.needsTiming && !plan.needsBookmarks)
  var timing = WireSpeechTiming(item, plan)
  var result = timing.finish(bytesPerFrame: 2, totalFrames: 5497), dry: [Float] = [], expected: [Float] = []
  let tone = ov_ios_tone(440, 20, 1, presentation.token)!
  defer { ov_ios_pcm_free(tone) }
  let insert = Array(UnsafeBufferPointer(start: ov_ios_samples(tone), count: ov_ios_frames(tone) * 2))
  var ends: [String: Int] = [:], resolutions: [String: String] = [:]
  for (i, text) in parts.enumerated() {
    guard case let .next(part, discard)? = result else { fatalError("Missing word timing fell back to the whole line") }
    precondition(part.text == text && part.voice == item.voice && part.rate == item.rate && discard == (i == 0))
    let voice = Float(i + 1) / 16
    dry += Array(repeating: voice, count: lengths[i])
    expected += insert
    ends["capital." + String(offsets[i])] = expected.count / 2
    expected += Array(repeating: voice, count: lengths[i] * 2)
    result = timing.finish(bytesPerFrame: 2, totalFrames: dry.count)
  }
  guard case let .ready(positions)? = result else { fatalError("The measured speech did not finish") }
  precondition(timing.report.measuredWords && timing.report.wordsReceived == 0)
  let points = positions.map { OvAnchorFrame(frame: UInt32($0.frame), precision: $0.precision == .exact ? 0 : 1) }
  let pcm = ov_ios_render_presentation(presentation.pointer, dry, dry.count, 44100, 1, points, points.count, presentation.token)!
  defer { ov_ios_pcm_free(pcm) }
  precondition(ov_ios_frames(pcm) * 2 == expected.count)
  precondition(expected.elementsEqual(UnsafeBufferPointer(start: ov_ios_samples(pcm), count: expected.count)))
  var reached: [String: Int] = [:]
  for region in presentation.regions(frames: ov_ios_frames(pcm))! {
    for line in region.events {
      let payload = Data(base64Encoded: String(line.split(separator: " ")[1]))!
      let value = try JSONSerialization.jsonObject(with: payload) as! [String: Any]
      guard let id = value["action_id"] as? String else { continue }
      if value["type"] as? String == "semantic_event_reached" { reached[id] = region.frames.upperBound }
      if let resolution = value["resolution"] as? String { resolutions[id] = resolution }
    }
  }
  precondition(reached == ends)
  for offset in offsets {
    precondition(resolutions["tone." + String(offset)] == (offset == 0 ? "exact" : "word_boundary"))
  }

  var timed = WireSpeechTiming(item, plan), source = 0, frame = 0
  for (i, text) in parts.enumerated() {
    timed.plan.observeWord(NSRange(location: source, length: text.trimmingCharacters(in: .whitespaces).utf16.count), byte: frame * 2)
    source += text.utf16.count
    frame += lengths[i]
  }
  guard case let .ready(same)? = timed.finish(bytesPerFrame: 2, totalFrames: frame) else { fatalError("Split a fully timed reading") }
  precondition(same.map(\.frame) == positions.map(\.frame) && !timed.report.measuredWords)
  var broken = plan
  for offset in offsets { broken.observeWord(NSRange(location: offset, length: 1), byte: 0) }
  precondition(broken.recoveryCuts(bytesPerFrame: 2, totalFrames: frame) == Array(offsets.dropFirst()))

  let mixed = WireItem(kind: .speech, text: "Café déjà TestCase end", anchors: [WireAnchor(offset: 13), WireAnchor(offset: 17)])
  var unicode = WireSpeechTiming(mixed, WireBookmarks(mixed)!)
  unicode.plan.observeWord(NSRange(location: 2, length: 3), byte: 100, matchesSource: false)
  guard case let .next(prefix, _)? = unicode.finish(bytesPerFrame: 2, totalFrames: 750),
        case let .next(wholeWord, _)? = unicode.finish(bytesPerFrame: 2, totalFrames: 250)
  else { fatalError("Lost the Unicode word boundary") }
  precondition(prefix.text == "Café déjà " && wholeWord.text == "TestCase " && unicode.report.wordsMismatched == 1)
  print("Five missing or unusable markers recovered at separate measured words. Rust tone samples and played semantic events match all five positions.")
}

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
  let unresolved = bookmarks.placements(bytesPerFrame: 2, totalFrames: 400)
  precondition(unresolved[1].precision == .span && unresolved[1].frame == 0)
  precondition(!bookmarks.acceptsWordRanges(in: bookmarks.ssml) && !bookmarks.acceptsWordRanges(in: "Cafe\u{301}Case & <x>"))
  precondition(bookmarks.acceptsWordRanges(in: "CaféCase & <x>"))
  bookmarks.observeWord(NSRange(location: NSNotFound, length: 4), byte: 320)
  precondition(bookmarks.placements(bytesPerFrame: 2, totalFrames: 400)[1].precision == .span)
  bookmarks.observeWord(NSRange(location: 4, length: 4), byte: 320)
  let approximate = bookmarks.placements(bytesPerFrame: 2, totalFrames: 400)[1]
  precondition(approximate.precision == .word && approximate.frame == 160)
  var after = innerMark
  after.after = true
  var trailing = WireBookmarks(WireItem(kind: .speech, text: "CaféCase", marks: [after]))!
  precondition(trailing.placements(bytesPerFrame: 4, totalFrames: 400)[0].frame == 400)
  trailing.observeWord(NSRange(location: 0, length: 4), byte: 80)
  precondition(trailing.placements(bytesPerFrame: 4, totalFrames: 400)[0].frame == 20)
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

// Verify the real negotiated dispatch against deterministic native speech and
// bookmark callbacks. Compare both inserted regions and every voice sample.
func checkTimelinePlayback(_ root: String, voices: String, envelope: Data) throws {
  let document = try JSONSerialization.jsonObject(with: envelope) as! [String: Any]
  func record(_ generation: Int, policy: String = "ordered", key: String? = nil,
              change: (inout [String: Any]) -> Void = { _ in }) throws -> String {
    var value = document
    value["generation"] = generation
    value["dispatch_id"] = generation
    value["delivery_policy"] = policy
    value["replacement_key"] = key
    change(&value)
    return "emacsvox_timeline " + (try JSONSerialization.data(withJSONObject: value)).base64EncodedString()
  }

  let output = TestOutput(root)
  var replies: [String] = []
  let lane = WireLane(output) { replies.append($0) }
  precondition(lane.setVoices(voices, preferred: "test-1"))
  try lane.feed("tts_split_caps 0", muted: false)
  let request = try record(1)
  let action = Array(request.utf8).withUnsafeBufferPointer { ov_ios_record(lane.worker, $0.baseAddress, $0.count) }!
  ov_ios_string_free(action)
  let plan = WirePresentation(ov_ios_take_presentation(lane.worker)!, key: nil, reply: { replies.append($0) })
  let item = plan.prepare(bundle: output.loader, personal: nil)!.first!
  precondition(item.text == "TestCase" && item.voice == "test-1" && item.anchors?.map(\.offset) == [0, 0, 4, 4])
  var marks = WireBookmarks(item)!
  marks.observe("ov-4", byte: 760)
  marks.observe(WireBookmarks.end, byte: 2000)
  let native = marks.placements(bytesPerFrame: 2, totalFrames: 1000)
  let points = native.map { OvAnchorFrame(frame: UInt32($0.frame), precision: $0.precision == .exact ? 0 : 2) }
  let dry = [Float](repeating: 0.125, count: 1000)
  let pcm = ov_ios_render_presentation(plan.pointer, dry, dry.count, 44100, 1, points, points.count, plan.token)!
  let tone = ov_ios_tone(440, 20, 1, plan.token)!
  defer { ov_ios_pcm_free(pcm); ov_ios_pcm_free(tone) }
  let count = ov_ios_frames(tone)
  precondition(count == 882 && ov_ios_frames(pcm) == 1000 + 2 * count)
  let insert = Array(UnsafeBufferPointer(start: ov_ios_samples(tone), count: count * 2))
  var expected = insert
  expected += [Float](repeating: 0.125, count: 380 * 2)
  expected += insert
  expected += [Float](repeating: 0.125, count: 620 * 2)
  precondition(expected.elementsEqual(UnsafeBufferPointer(start: ov_ios_samples(pcm), count: expected.count)))
  let regions = plan.regions(frames: ov_ios_frames(pcm))!
  var semantic: [String: Int] = [:], previous = 0
  for region in regions {
    precondition(region.frames.lowerBound == previous)
    previous = region.frames.upperBound
    for line in region.events {
      let data = Data(base64Encoded: line.split(separator: " ")[1].description)!
      let value = try JSONSerialization.jsonObject(with: data) as! [String: Any]
      if value["type"] as? String == "semantic_event_reached" { semantic[value["action_id"] as! String] = previous }
    }
  }
  precondition(semantic == ["semantic.2": count, "semantic.4": 380 + 2 * count])
  precondition(previous == ov_ios_frames(pcm) && replies.isEmpty)

  output.hold = true
  func feed(_ record: String) throws { try lane.feed(record, muted: false) }
  try feed(record(2, policy: "replaceable", key: "nav"))
  try feed(record(3, policy: "urgent"))
  try feed(record(4, policy: "replaceable", key: "nav"))
  precondition(replies == ["__EMACSVOX_TRACKED__ 2 cancelled"])
  output.finishes[0](true)
  precondition(replies.count == 1)
  output.finishes[1](true)
  precondition(replies.last == "__EMACSVOX_TRACKED__ 3 completed")
  output.finishes[2](true)
  precondition(replies.last == "__EMACSVOX_TRACKED__ 4 completed")
  try lane.feed(record(5), muted: true)
  precondition(replies.last == "__EMACSVOX_TRACKED__ 5 cancelled")
  try feed(record(4))
  precondition(replies.last == "__EMACSVOX_TRACKED__ 4 cancelled")
  var synthesized = false
  output.observeSpeech = { _ in synthesized = true }
  try feed(record(6) { value in
    var spans = value["spans"] as! [[String: Any]]
    spans.append(["id": 2, "text": "Later span"])
    value["spans"] = spans
    value["actions"] = [["id":"missing", "position":["position":"span_boundary", "span_id":2, "affinity":"before"],
                         "lifecycle_anchor":"run", "type":"audio", "path":"omnivox-icon:packs/accent/absent.ogg",
                         "mode":"insert","volume":1,"pan":0.5,"effect_bus":"dry"]]
  })
  precondition(!synthesized && replies.last == "__EMACSVOX_TRACKED__ 6 failed")

  // Preserve ordered work under pressure. Evict old queued navigation first.
  output.finishes.removeAll()
  try feed(record(7))
  try feed(record(8, policy: "replaceable", key: "other"))
  for id in 9...39 { try feed(record(id)) }
  try feed(record(40))
  precondition(replies.last == "__EMACSVOX_TRACKED__ 8 cancelled")
  try feed(record(41))
  precondition(replies.last == "__EMACSVOX_TRACKED__ 41 failed")
  lane.stop()
  let stopped = replies
  output.finishes.forEach { $0(true) }
  precondition(replies == stopped)
  output.hold = false
  var heard: [WireItem] = []
  output.observeSpeech = { heard.append($0) }
  let fixtureURL = URL(fileURLWithPath: "/out/TimelineV3.json")
  var fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as! [String: Any]
  var actions = fixture["actions"] as! [[String: Any]]
  actions[0]["path"] = "omnivox-icon:packs/accent/open-object.ogg"
  fixture["actions"] = actions
  fixture["generation"] = 42
  fixture["dispatch_id"] = 42
  try feed("emacsvox_timeline " + (try JSONSerialization.data(withJSONObject: fixture)).base64EncodedString())
  precondition(heard.map(\.text) == ["Hello world", "Done"])
  precondition(replies.last == "__EMACSVOX_TRACKED__ 42 completed")
  let events = try replies.dropFirst(stopped.count).compactMap { line -> [String: Any]? in
    guard line.hasPrefix("__EMACSVOX_MARKER__ "), let payload = line.split(separator: " ").last,
          let data = Data(base64Encoded: String(payload)) else { return nil }
    return try JSONSerialization.jsonObject(with: data) as? [String: Any]
  }
  precondition(events.contains { $0["type"] as? String == "semantic_event_reached" && $0["action_id"] as? String == "done-reached" })
  print("Passed exact TestCase PCM and semantic frames, protected ordering, queue pressure, atomic resource failure and stale playback callbacks.")
}
