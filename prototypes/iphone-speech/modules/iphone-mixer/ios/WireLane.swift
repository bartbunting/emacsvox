// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import OmnivoxMobile

// Both speech workers use one platform catalogue for this connection.
final class WireVoiceInventory {
  private struct ControlHeader: Decodable { let type: String }
  private var changed = true
  func invalidate() { changed = true }

  func refresh(for record: String, _ read: () throws -> Void) rethrows {
    guard changed || Self.requestsInventory(record) else { return }
    changed = false
    do { try read() } catch { changed = true; throw error }
  }

  private static func requestsInventory(_ record: String) -> Bool {
    let command = "omnivox_control"
    guard record.hasPrefix(command) else { return false }
    let rest = record.dropFirst(command.count)
    guard rest.first?.isWhitespace == true else { return false }
    var payload = rest.trimmingCharacters(in: .whitespaces)[...]
    if payload.first == "{", payload.last == "}" { payload = payload.dropFirst().dropLast() }
    guard let data = Data(base64Encoded: String(payload)),
          let header = try? JSONDecoder().decode(ControlHeader.self, from: data) else { return false }
    return header.type == "inventory"
  }
}

final class WireLane {
  let worker = ov_ios_worker_new()!
  let schedule: WireSchedule
  private var expiry: DispatchWorkItem?
  private let reply: (String) -> Void
  init(_ output: WireOutput, reply: @escaping (String) -> Void) {
    self.reply = reply
    schedule = WireSchedule(output, reply: reply)
  }
  func setVoices(_ json: String, preferred: String) -> Bool {
    ov_ios_set_voices(worker, json, preferred)
  }
  deinit { expiry?.cancel(); ov_ios_worker_free(worker) }
  func stop() {
    // Clear the Rust pending batch as well as already admitted playback.
    var command = UInt8(ascii: "s")
    if let result = ov_ios_record(worker, &command, 1) { ov_ios_string_free(result) }
    refreshParts()
    schedule.stop(all: true)
  }
  private func refreshParts() {
    expiry?.cancel()
    expiry = nil
    let ms = ov_ios_parts_remaining(worker)
    while let value = ov_ios_take_notice(worker) {
      reply(String(cString: value))
      ov_ios_string_free(value)
    }
    if ms >= 0 {
      let task = DispatchWorkItem { [weak self] in self?.refreshParts() }
      expiry = task
      DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Int(ms)), execute: task)
    }
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
  func speechItem(_ text: String) throws -> WireItem? {
    let words = text.components(separatedBy: .newlines).joined(separator: " ")
    let value = Data(words.utf8).withUnsafeBytes { bytes in
      ov_ios_local_speech(worker, bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count)
    }
    guard let value else { return nil }
    defer { ov_ios_string_free(value) }
    return try JSONDecoder().decode(WireItem.self, from: Data(bytes: value, count: strlen(value)))
  }
  func timingSample(_ envelope: Data) throws -> [WireItem]? {
    let payload = envelope.base64EncodedData()
    let result = payload.withUnsafeBytes { bytes in
      ov_ios_timing_sample(worker, bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count)
    }
    guard let result else { return nil }
    defer { ov_ios_string_free(result) }
    return try JSONDecoder().decode([WireItem].self, from: Data(bytes: result, count: strlen(result)))
  }
  func permission(_ text: String, done: @escaping (Bool) -> Void) throws {
    guard let item = try speechItem(text) else { done(false); return }
    schedule.permission(item, done: done)
  }
  func feed(_ line: String, muted: Bool) throws {
    if muted, let prefix = ["emacsvox_tracked_dispatch ", "emacsvox_marker_dispatch "].first(where: { line.hasPrefix($0) }) {
      if let id = UInt64(line.dropFirst(prefix.count)), id > 0 {
        reply("__EMACSVOX_TRACKED__ " + String(id) + " cancelled")
      }
      return
    }
    if muted && !(line.hasPrefix("emacsvox_timeline") || line.hasPrefix("emacsvox_letter ") || line.hasPrefix("omnivox_control ") || line.hasPrefix("tts_set_") ||
                  line.hasPrefix("tts_sync_state ") || line == "tts_reset" || line == "s") { return }
    let result = try self.action(line)
    refreshParts()
    guard let (action, size) = result else { return }
    if action.op == .timeline || action.op == .preview, let pointer = ov_ios_take_presentation(worker) {
      let preview = action.op == .preview ? ov_ios_take_preview(pointer) : nil
      let plan = WirePresentation(pointer, key: action.key, preview: preview, reply: reply)
      if muted {
        plan.finishPreview(OvPreviewCancelled)
        if let receipts = action.receipts { reply(receipts.cancelled) }
      } else { schedule.submit(action, bytes: size, presentation: plan) }
      return
    }
    if muted && action.op == .batch {
      if let receipts = action.receipts { schedule.submit(WireAction(op: .reply, line: receipts.cancelled), bytes: 0) }
    } else { schedule.submit(action, bytes: size) }
  }
}
