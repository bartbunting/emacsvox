// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import OmnivoxMobile

// WSL harness. Synthetic voice durations are controlled by the test. Effects
// still go through the Rust renderer and remote icon decoder used on device.
final class TestOutput: WireOutput {
  let loader: OpaquePointer, token = ov_ios_token_new()!
  var hold = false, playPreviewFirstFrame = false
  var started: [WireItem.Kind] = [], finishes: [(Bool) -> Void] = []
  var observeSpeech: ((WireItem) -> Void)?
  init(_ root: String) { loader = ov_ios_loader_new(root)! }
  deinit { ov_ios_loader_free(loader); ov_ios_token_free(token) }
  var mixed: ((ArraySlice<WireItem>, @escaping () -> () -> Void, @escaping (Int, Bool) -> Void) -> Void)?
  var stopMixed: (() -> Void)?
  func playMixed(_ items: ArraySlice<WireItem>, reached: @escaping (String) -> Void, holdTail: @escaping () -> () -> Void, done: @escaping (Int, Bool) -> Void) {
    if let mixed { mixed(items, holdTail, done) }
    else if items.contains(where: { $0.startMarker != nil }) {
      let finish: (Bool) -> Void = { ok in
        if ok { for item in items { if let marker = item.startMarker { reached(marker) } } }
        done(items.count, ok)
      }
      if hold { finishes.append(finish) } else { finish(true) }
    } else { done(0, true) }
  }
  func playTimeline(_ plan: WirePresentation, holdTail: @escaping () -> () -> Void, done: @escaping (Bool) -> Void) {
    guard let items = plan.prepare(bundle: loader, personal: nil) else { done(false); return }
    var reached: [String] = []
    for item in items {
      // The single-word fixture has named bookmarks. Other readings receive
      // audio only, as on the reported handset.
      var timing = WireSpeechTiming(item, WireBookmarks(item)!)
      var frames = 4096
      if item.text == "TestCase" {
        timing.plan.observe("ov-4", byte: 3780)
        timing.plan.observe(WireBookmarks.end, byte: frames * 2)
      }
      var result = timing.finish(bytesPerFrame: 2, totalFrames: frames)
      while case let .next(part, discard)? = result {
        if discard { frames = 0 }
        frames += 1100 + (part.text?.utf8.count ?? 0)
        result = timing.finish(bytesPerFrame: 2, totalFrames: frames)
      }
      guard case let .ready(positions)? = result else { done(false); return }
      let points = positions.map {
        OvAnchorFrame(frame: UInt32($0.frame), precision: $0.precision == .exact ? 0 : $0.precision == .word ? 1 : 2)
      }
      let samples = [Float](repeating: 0.125, count: frames)
      guard let pcm = ov_ios_render_presentation(plan.pointer, samples, samples.count, 44100, 1, points, points.count, plan.token)
      else { done(false); return }
      let regions = plan.regions(frames: ov_ios_frames(pcm))
      ov_ios_pcm_free(pcm)
      guard let regions else { done(false); return }
      if plan.isPreview {
        plan.acceptedAudio()
        if playPreviewFirstFrame { plan.startedAudio() }
      }
      reached += regions.flatMap(\.events)
      observeSpeech?(item)
    }
    let endTail = ov_ios_presentation_tail(plan.pointer).map { pcm in
      ov_ios_pcm_free(pcm)
      return holdTail()
    }
    let finish: (Bool) -> Void = { ok in
      if ok {
        if plan.isPreview && !items.isEmpty { plan.startedAudio() }
        plan.reached(reached)
      }
      done(ok)
      endTail?()
    }
    if hold { finishes.append(finish) } else { finish(true) }
  }
  func play(_ item: WireItem, done: @escaping (Bool) -> Void) {
    started.append(item.kind)
    let pcm: OpaquePointer?
    switch item.kind {
    case .tone: pcm = item.tonePCM(token)
    case .sound: pcm = ov_ios_sound(loader, item.path!, item.gain!, token)
    default:
      if item.kind == .speech { observeSpeech?(item) }
      if hold { finishes.append(done) } else { done(true) }
      return
    }
    if let pcm {
      precondition(ov_ios_frames(pcm) > 0)
      ov_ios_pcm_free(pcm)
    }
    if hold { finishes.append(done) } else { done(pcm != nil) }
  }
  func stop(all: Bool) { stopMixed?() }
}

@main struct Probe {
  static func main() throws {
    let output = TestOutput(CommandLine.arguments[1])
    let voices = #"[{"id":"test-1","name":"Fixture","language":"en-US","quality":"compact"},{"id":"test-2","name":"Fixture","language":"en-AU","quality":"enhanced"}]"#
    var replies = [String]()
    let interactive = CommandLine.arguments.count == 2
    let lane = WireLane(output) { line in
      if interactive { FileHandle.standardOutput.write(Data((line + "\n").utf8)) }
      else { replies.append(line) }
    }
    precondition(lane.setVoices(voices, preferred: "test-1"))
    func feed(_ line: String) throws { try lane.feed(line, muted: false) }
    if !interactive {
      let trace = WireSpeechTrace()
      var level = WireTraceLevel()
      [Float(1), -1, 0.5, -0.5].withUnsafeBufferPointer { level.observe($0) }
      precondition(level.peak == 1 && level.fullScale == 2 && level.samples == 4 &&
                   abs(level.rms - sqrt(0.625)) < 0.000001)
      func disabledText() -> String { fatalError("Read speech text while logging was disabled") }
      precondition(trace.begin(disabledText()) == nil && trace.snapshot().isEmpty)
      trace.setEnabled(true)
      let old = trace.begin("Lime Plum")
      trace.append(old, "Word at 5")
      precondition(trace.snapshot().contains("Lime Plum") && trace.snapshot().contains("Word at 5"))
      trace.setEnabled(false)
      trace.setEnabled(true)
      trace.append(old, disabledText())
      precondition(trace.snapshot().isEmpty)
      _ = trace.begin(String(repeating: "🦜", count: 22000))
      precondition(trace.snapshot().utf8.count <= 65536 && trace.snapshot().hasSuffix("[entry truncated]") && !trace.snapshot().contains("�"))
      var letters: [WireItem] = []
      output.observeSpeech = { letters.append($0) }
      try feed("tts_set_pitch_multiplier 0.8")
      try feed("l {j}")
      try feed("l {J}")
      try feed("tts_say {ordinary}")
      precondition(letters.map(\.text) == ["j", "j", "ordinary"])
      precondition(letters.map(\.pitch) == [0.8, 1.5, 0.8])
      output.observeSpeech = nil
      output.started.removeAll()
      try feed("tts_set_pitch_multiplier 1")
      let envelope = try Data(contentsOf: URL(fileURLWithPath: "/out/CapitalTiming.json"))
      try feed("tts_set_voice {test-2}")
      try feed("tts_split_caps 0")
      try feed("tts_set_tone_volume 0.5")
      let items = try lane.timingSample(envelope)
      guard let sample = items?.first, items?.count == 1, let marks = sample.marks else {
        fatalError("Desktop timing sample did not produce one marked utterance")
      }
      precondition(sample.text == "TestCase" && sample.voice == "test-2")
      precondition(marks.map(\.offset) == [0, 4])
      precondition(marks.allSatisfy { $0.hz == 440 && $0.ms == 20 && $0.gain == 0.5 && $0.placement == .insert })
      try feed("tts_set_tone_volume 1")
      try feed("tts_set_voice {test-1}")
      print("The desktop timeline supplied one intact TestCase with both capital positions and the selected phone voice.")
      try checkShapedTones(CommandLine.arguments[1])
      try checkPrivatePreview(CommandLine.arguments[1], voices: voices)
      try checkPalettePlayback(CommandLine.arguments[1], voices: voices)
      try checkTimelinePlayback(CommandLine.arguments[1], voices: voices, envelope: envelope)
      try checkMissingWordTiming(CommandLine.arguments[1], voices: voices, envelope: envelope)
      try checkMixedPlayback(CommandLine.arguments[1], voices: voices)
      let token = ov_ios_token_new()!
      let pcm = ov_ios_tone(660, 480, 1, token)!
      let quieter = ov_ios_tone(660, 480, 0.5, token)!
      precondition(ov_ios_frames(pcm) == 21168 && ov_ios_frames(quieter) == ov_ios_frames(pcm))
      let samples = ov_ios_samples(pcm)!, half = ov_ios_samples(quieter)!
      precondition(samples[0] == 0 && samples[42335] == 0 && samples[1000] != samples[1001])
      for i in 0..<42336 { precondition(samples[i] * 0.5 == half[i]) }
      ov_ios_cancel(token)
      precondition(ov_ios_tone(440, 480, 1, token) == nil)
      ov_ios_pcm_free(quieter)
      ov_ios_pcm_free(pcm)
      ov_ios_token_free(token)
      output.hold = true
      for line in ["q first", "a omnivox-icon:packs/accent/open-object.ogg", "q second", "t 550 40", "emacsvox_tracked_dispatch 99"] { try feed(line) }
      precondition(output.started == [.tone, .speech])
      output.finishes[1](true)
      precondition(output.started == [.tone, .speech, .sound, .speech])
      output.finishes[3](true)
      precondition(replies.isEmpty)
      output.finishes[2](true)
      precondition(replies.isEmpty)
      output.finishes[0](true)
      precondition(replies == ["__EMACSVOX_TRACKED__ 99 completed"])
      try feed("q old")
      try feed("emacsvox_tracked_dispatch 100")
      try feed("s")
      output.finishes.last?(true)
      precondition(replies.last == "__EMACSVOX_TRACKED__ 100 cancelled" && replies.count == 2)
      output.started.removeAll()
      output.finishes.removeAll()
      for line in ["q first", "emacsvox_tone 1 insert 330 12", "emacsvox_tone 1 overlay 550 25", "q last", "emacsvox_tracked_dispatch 101"] { try feed(line) }
      precondition(output.started == [.speech])
      output.finishes[0](true)
      precondition(output.started == [.speech, .tone])
      output.finishes[1](true)
      precondition(output.started == [.speech, .tone, .tone, .speech])
      output.finishes[3](true)
      precondition(replies.count == 2)
      output.finishes[2](true)
      precondition(replies.last == "__EMACSVOX_TRACKED__ 101 completed")
      // Stop silences a lane immediately while leaving the other worker running.
      let urgentOutput = TestOutput(CommandLine.arguments[1])
      urgentOutput.hold = true
      let notify = WireLane(urgentOutput, reply: { _ in })
      precondition(notify.setVoices(voices, preferred: "test-2"))
      var permitted: Bool?
      try notify.permission("Allow once or reject") { permitted = $0 }
      try feed("q line one")
      try feed("d")
      lane.stop()
      try feed("q line two")
      try feed("d")
      precondition(permitted == nil && urgentOutput.started == [.speech])
      urgentOutput.finishes[0](true)
      precondition(permitted == true)
      lane.stop()
      let count = output.started.count
      try lane.feed("q stale", muted: true)
      try lane.feed("emacsvox_tracked_dispatch 102", muted: true)
      try feed("d")
      precondition(output.started.count == count && replies.last == "__EMACSVOX_TRACKED__ 102 cancelled")
      print("Passed tone and speech overlap, queued recording boundary, played tails and stale callback after Stop.")
      return
    }
    while let line = readLine() {
      switch line {
      case "test-hold": output.hold = true
      case "test-permission":
        output.hold = true
        try lane.permission("Allow once or reject") { ok in
          FileHandle.standardOutput.write(Data(("test-audio permission " + (ok ? "played" : "cancelled") + "\n").utf8))
        }
      case "test-play":
        output.hold = false
        let callbacks = output.finishes
        output.finishes.removeAll()
        for played in callbacks { played(true) }
      default: try feed(line)
      }
      if line == "tts_exit" { break }
    }
  }
}
