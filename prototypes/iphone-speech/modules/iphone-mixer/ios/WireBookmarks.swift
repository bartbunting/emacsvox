// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import OmnivoxMobile

struct WireTimingReport {
  var exact = 0, word = 0, span = 0
  var description: String {
    var text = "The voice supplied \(exact) of \(exact + word + span) in-word timing marks."
    if word > 0 { text += " \(word) used a word boundary." }
    if span > 0 { text += " \(span) used the speech span boundary." }
    return text
  }
}

// Keep one utterance and add an SSML bookmark at each requested UTF-8
// boundary. Apple ignores utterance rate and pitch when the input is SSML.
struct WireBookmarks {
  let ssml: String, marks: [WireToneMark], length: Int
  private let source: String, utf16Length: Int
  private(set) var offsets: [String: Int] = [:]
  private var conflicting: Set<String> = []
  private var words: [Int: Int] = [:], conflictingWords: Set<Int> = []
  static let end = "ov-end"

  init?(_ item: WireItem) {
    guard let text = item.text, let marks = item.marks, !marks.isEmpty, marks.count <= 512 else { return nil }
    let bytes = Array(text.utf8)
    self.marks = marks
    source = text
    utf16Length = text.utf16.count
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

  func acceptsWordRanges(in request: String) -> Bool {
    // SSML and canonically equivalent Unicode can both have different indices.
    source.utf8.elementsEqual(request.utf8)
  }

  mutating func observeWord(_ range: NSRange, byte: Int) {
    guard byte >= 0, range.location >= 0, range.location <= utf16Length,
          range.length > 0, range.length <= utf16Length - range.location,
          let word = Range(range, in: source) else { return }
    let offset = source.utf8.distance(from: source.utf8.startIndex, to: word.lowerBound)
    guard words.count < 4096 || words[offset] != nil else { return }
    if let previous = words[offset], previous != byte { conflictingWords.insert(offset) }
    words[offset] = byte
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

  enum Precision { case exact, word, span }
  func placements(bytesPerFrame: Int, totalFrames: Int) -> [(frame: Int, precision: Precision)] {
    guard bytesPerFrame > 0, totalFrames > 0 else { return [] }
    var boundaries: [OvWordBoundary] = []
    for (offset, byte) in words.sorted(by: { $0.key < $1.key }) {
      let frame = byte / bytesPerFrame
      guard !conflictingWords.contains(offset), byte % bytesPerFrame == 0,
            frame <= totalFrames, frame >= Int(boundaries.last?.frame ?? 0) else { continue }
      boundaries.append(OvWordBoundary(offset: UInt32(offset), frame: UInt32(frame)))
    }
    let exact = nativeFrames(bytesPerFrame: bytesPerFrame, totalFrames: totalFrames)
    return boundaries.withUnsafeBufferPointer { words in
      zip(marks, exact).map { mark, frame in
        if let frame { return (frame, .exact) }
        let after = mark.after == true
        var word: UInt32 = 0
        if ov_ios_word_frame(UInt32(mark.offset), after, words.baseAddress, words.count, &word) {
          return (Int(word), .word)
        }
        return (after ? totalFrames : 0, .span)
      }
    }
  }
}
