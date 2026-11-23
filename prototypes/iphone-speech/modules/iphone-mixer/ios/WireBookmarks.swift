// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

// Keep one utterance and add an SSML bookmark at each requested UTF-8
// boundary. Apple ignores utterance rate and pitch when the input is SSML.
struct WireBookmarks {
  let ssml: String, marks: [WireToneMark], length: Int
  private(set) var offsets: [String: Int] = [:]
  private var conflicting: Set<String> = []
  static let end = "ov-end"

  init?(_ item: WireItem) {
    guard let text = item.text, let marks = item.marks, !marks.isEmpty, marks.count <= 512 else { return nil }
    let bytes = Array(text.utf8)
    self.marks = marks
    length = bytes.count
    let rate = Int(((item.rate ?? 1) * 100).rounded())
    let pitch = Int((((item.pitch ?? 1) - 1) * 100).rounded())
    let gain = item.gain ?? 1
    let volume = gain > 0 ? String(format: "%.2fdB", locale: Locale(identifier: "en_US_POSIX"), 20 * log10(Double(gain))) : "silent"
    var xml = "<speak version=\"1.0\" xmlns=\"http://www.w3.org/2001/10/synthesis\"><prosody rate=\"\(max(1, rate))%\" pitch=\"\(pitch >= 0 ? "+" : "")\(pitch)%\" volume=\"\(volume)\">"
    var start = 0
    func escaped(_ low: Int, _ high: Int) -> String? {
      guard let part = String(bytes: bytes[low..<high], encoding: .utf8) else { return nil }
      return part.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
    }
    for offset in Set(marks.map(\.offset)).sorted() {
      guard (start...length).contains(offset), let part = escaped(start, offset) else { return nil }
      xml += part + "<mark name=\"ov-\(offset)\"/>"
      start = offset
    }
    guard let rest = escaped(start, length) else { return nil }
    ssml = xml + rest + "<mark name=\"\(Self.end)\"/></prosody></speak>"
  }

  mutating func observe(_ name: String, byte: Int) {
    guard byte >= 0, name == Self.end || marks.contains(where: { name == "ov-\($0.offset)" }) else { return }
    if let previous = offsets[name], previous != byte { conflicting.insert(name) }
    offsets[name] = byte
  }

  var complete: Bool { offsets[Self.end] != nil && marks.allSatisfy { offsets["ov-\($0.offset)"] != nil } }

  func nativeFrames(bytesPerFrame: Int, totalFrames: Int) -> [Int?] {
    guard bytesPerFrame > 0, totalFrames > 0 else { return marks.map { _ in nil } }
    func aligned(_ name: String) -> Int? {
      guard !conflicting.contains(name), let b = offsets[name], b % bytesPerFrame == 0,
            b / bytesPerFrame <= totalFrames else { return nil }
      return b / bytesPerFrame
    }
    var last = -1
    var byOffset: [Int: Int] = [:]
    let endFrame = aligned(Self.end) ?? totalFrames
    for offset in Set(marks.map(\.offset)).sorted() {
      // A span edge is defined by the protocol even if the voice omits marks.
      if offset == 0 { byOffset[offset] = 0; last = aligned("ov-0") ?? 0; continue }
      if offset == length { byOffset[offset] = totalFrames; continue }
      if let frame = aligned("ov-\(offset)"), frame > max(0, last), frame < endFrame {
        byOffset[offset] = frame
        last = frame
      }
    }
    return marks.map { byOffset[$0.offset] }
  }
}
