// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import OmnivoxMobile

// WSL harness. Synthetic voice durations are controlled by the test. Effects
// still go through the Rust renderer and remote icon decoder used on device.
final class TestOutput: WireOutput {
  let loader: OpaquePointer, token = ov_ios_token_new()!
  var hold = false
  var started: [WireItem.Kind] = [], finishes: [(Bool) -> Void] = []
  init(_ root: String) { loader = ov_ios_loader_new(root)! }
  deinit { ov_ios_loader_free(loader); ov_ios_token_free(token) }
  func play(_ item: WireItem, done: @escaping (Bool) -> Void) {
    started.append(item.kind)
    let pcm: OpaquePointer?
    switch item.kind {
    case .tone: pcm = ov_ios_tone(item.hz!, item.ms!, item.gain!, token)
    case .sound: pcm = ov_ios_sound(loader, item.path!, item.gain!, token)
    default:
      if hold { finishes.append(done) } else { done(true) }
      return
    }
    if let pcm {
      precondition(ov_ios_frames(pcm) > 0)
      ov_ios_pcm_free(pcm)
    }
    if hold { finishes.append(done) } else { done(pcm != nil) }
  }
  func stop(all: Bool) {}
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
      try feed(line)
      if line == "tts_exit" { break }
    }
  }
}
