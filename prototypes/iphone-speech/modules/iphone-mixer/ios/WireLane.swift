// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import OmnivoxMobile

final class WireLane {
  let worker = ov_ios_worker_new()!
  let schedule: WireSchedule
  private let reply: (String) -> Void
  init(_ output: WireOutput, reply: @escaping (String) -> Void) {
    self.reply = reply
    schedule = WireSchedule(output, reply: reply)
  }
  func setVoices(_ json: String, preferred: String) -> Bool {
    ov_ios_set_voices(worker, json, preferred)
  }
  deinit { ov_ios_worker_free(worker) }
  func stop() {
    // Clear the Rust pending batch as well as already admitted playback.
    var command = UInt8(ascii: "s")
    if let result = ov_ios_record(worker, &command, 1) { ov_ios_string_free(result) }
    schedule.stop(all: true)
  }
  private func action(_ line: String) throws -> (WireAction, Int)? {
    let data = Data(line.utf8)
    let result = data.withUnsafeBytes { bytes in
      ov_ios_record(worker, bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count)
    }
    guard let result else { return nil }
    defer { ov_ios_string_free(result) }
    let payload = Data(bytes: result, count: strlen(result))
    return (try JSONDecoder().decode(WireAction.self, from: payload), payload.count)
  }
  func permission(_ text: String, done: @escaping (Bool) -> Void) throws {
    let words = text.components(separatedBy: .newlines).joined(separator: " ")
    guard let (command, _) = try action("tts_say {" + words + "}"), let item = command.item else { done(false); return }
    schedule.permission(item, done: done)
  }
  func feed(_ line: String, muted: Bool) throws {
    if muted, line.hasPrefix("emacsvox_tracked_dispatch ") {
      if let id = UInt64(line.dropFirst("emacsvox_tracked_dispatch ".count)), id > 0 {
        reply("__EMACSVOX_TRACKED__ " + String(id) + " cancelled")
      }
      return
    }
    if muted && !(line.hasPrefix("omnivox_control ") || line.hasPrefix("tts_set_") ||
                  line.hasPrefix("tts_sync_state ") || line == "tts_reset" || line == "s") { return }
    guard let (action, size) = try self.action(line) else { return }
    if muted && action.op == .batch {
      if let receipts = action.receipts { schedule.submit(WireAction(op: .reply, line: receipts.cancelled), bytes: 0) }
    } else { schedule.submit(action, bytes: size) }
  }
}
