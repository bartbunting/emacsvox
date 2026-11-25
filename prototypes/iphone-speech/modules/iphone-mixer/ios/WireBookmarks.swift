// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import OmnivoxMobile

struct WireTimingReport {
  var exact = 0, word = 0, span = 0
  var requestedBookmarks = false, measuredWords = false
  var bookmarksReceived = 0, wordsReceived = 0, wordsMismatched = 0, wordStartsUsed = 0
  var description: String {
    var text = "Cue timing. \(exact) exact, \(word) at word boundaries, \(span) at speech span boundaries."
    if requestedBookmarks { text += " Apple returned \(bookmarksReceived) named bookmarks." }
    text += " The first reading returned \(wordsReceived) word ranges with \(wordStartsUsed) usable word positions."
    if wordsMismatched > 0 { text += " \(wordsMismatched) ranges referred to different text." }
    if measuredWords { text += " Word starts were measured from separately synthesized audio." }
    return text
  }
}

// Use plain text for word timing. Only positions inside words need SSML.
struct WireBookmarks {
  let ssml: String, marks: [WireAnchor], length: Int
  let wordStarts: [Int]
  private let bookmarkNames: Set<String>
  private let orderedOffsets: [Int]
  private let source: String, utf16Length: Int
  private(set) var offsets: [String: Int] = [:]
  private var conflicting: Set<String> = []
  private var words: [Int: Int] = [:], conflictingWords: Set<Int> = []
  private var bookmarksReceived = 0, wordsReceived = 0, wordsMismatched = 0
  static let end = "ov-end"

  var isWhitespaceOnly: Bool { !source.isEmpty && source.allSatisfy(\.isWhitespace) }

  init?(_ item: WireItem) {
    guard let text = item.text, let marks = item.anchors ?? item.marks?.map({ WireAnchor(offset: $0.offset, after: $0.after) }),
          item.anchors != nil || !marks.isEmpty, marks.count <= 512 else { return nil }
    self.marks = marks
    source = text
    utf16Length = text.utf16.count
    let byteCount = text.utf8.count
    length = byteCount
    guard marks.allSatisfy({ (0...byteCount).contains($0.offset) }) else { return nil }
    // Endpoints already have exact sample positions. Most navigated lines
    // need neither Unicode word boundaries nor an SSML synthesis request.
    guard marks.contains(where: { $0.offset > 0 && $0.offset < byteCount }) else {
      wordStarts = []
      bookmarkNames = []
      orderedOffsets = []
      ssml = ""
      return
    }
    // ICU's Unicode word breaks keep contractions and mixed-case words intact.
    wordStarts = Self.wordStart.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
      guard let start = Range(NSRange(location: $0.range.location, length: 0), in: text)?.lowerBound else { return nil }
      return text.utf8.distance(from: text.utf8.startIndex, to: start)
    }
    orderedOffsets = Set(marks.map(\.offset)).sorted()
    bookmarkNames = Set(orderedOffsets.map { "ov-\($0)" })
    let starts = wordStarts
    guard orderedOffsets.contains(where: { offset in
      guard offset > 0 && offset < byteCount else { return false }
      let index = Self.firstAtLeast(offset, in: starts)
      return index == starts.count || starts[index] != offset
    }) else {
      ssml = ""
      return
    }
    let bytes = Array(text.utf8)
    let rate = Int(((item.rate ?? 1) * 100).rounded())
    let pitch = Int((((item.pitch ?? 1) - 1) * 100).rounded())
    let gain = item.gain ?? 1
    let volume: String
    if gain == 1 { volume = "0.00dB" }
    else if gain <= 0 { volume = "silent" }
    else { volume = String(format: "%.2fdB", locale: Self.posix, 20 * log10(Double(gain))) }
    var xml = "<speak version=\"1.0\" xmlns=\"http://www.w3.org/2001/10/synthesis\"><prosody rate=\"\(max(1, rate))%\" pitch=\"\(pitch >= 0 ? "+" : "")\(pitch)%\" volume=\"\(volume)\">"
    var start = 0
    func escaped(_ low: Int, _ high: Int) -> String? {
      let slice = bytes[low..<high]
      guard let part = String(bytes: slice, encoding: .utf8) else { return nil }
      guard slice.contains(where: { $0 == 38 || $0 == 60 || $0 == 62 }) else { return part }
      return part.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
    }
    for offset in orderedOffsets {
      guard (start...length).contains(offset), let part = escaped(start, offset) else { return nil }
      xml += part + "<mark name=\"ov-\(offset)\"/>"
      start = offset
    }
    guard let rest = escaped(start, length) else { return nil }
    ssml = xml + rest + "<mark name=\"\(Self.end)\"/></prosody></speak>"
  }

  private static let wordStart = try! NSRegularExpression(pattern: #"(?w)\b[\p{L}\p{M}\p{N}\p{Pc}]"#)
  private static let posix = Locale(identifier: "en_US_POSIX")

  static func firstAtLeast(_ value: Int, in sorted: [Int]) -> Int {
    var low = 0, high = sorted.count
    while low < high {
      let middle = low + (high - low) / 2
      if sorted[middle] < value { low = middle + 1 } else { high = middle }
    }
    return low
  }

  mutating func observe(_ name: String, byte: Int) {
    bookmarksReceived += 1
    guard byte >= 0, name == Self.end || bookmarkNames.contains(name) else { return }
    if let previous = offsets[name], previous != byte { conflicting.insert(name) }
    offsets[name] = byte
  }

  func acceptsWordRanges(in request: String) -> Bool {
    // SSML and canonically equivalent Unicode can both have different indices.
    source.utf8.elementsEqual(request.utf8)
  }

  mutating func observeWord(_ range: NSRange, byte: Int, matchesSource: Bool = true) {
    wordsReceived += 1
    guard matchesSource else { wordsMismatched += 1; return }
    guard byte >= 0, range.location >= 0, range.location <= utf16Length,
          range.length > 0, range.length <= utf16Length - range.location,
          let word = Range(range, in: source) else { return }
    let offset = source.utf8.distance(from: source.utf8.startIndex, to: word.lowerBound)
    guard words.count < 4096 || words[offset] != nil else { return }
    if let previous = words[offset], previous != byte { conflictingWords.insert(offset) }
    words[offset] = byte
  }

  var needsTiming: Bool { marks.contains { $0.offset > 0 && $0.offset < length } }
  var needsBookmarks: Bool { !ssml.isEmpty }

  var complete: Bool {
    marks.allSatisfy {
      $0.offset == 0 || $0.offset == length || words[$0.offset] != nil ||
        (offsets[Self.end] != nil && offsets["ov-\($0.offset)"] != nil)
    }
  }

  func nativeFrames(bytesPerFrame: Int, totalFrames: Int) -> [Int?] {
    guard bytesPerFrame > 0, totalFrames > 0 else { return marks.map { _ in nil } }
    if orderedOffsets.isEmpty { return marks.map { $0.offset == 0 ? 0 : totalFrames } }
    func aligned(_ name: String) -> Int? {
      guard !conflicting.contains(name), let b = offsets[name], b % bytesPerFrame == 0,
            b / bytesPerFrame <= totalFrames else { return nil }
      return b / bytesPerFrame
    }
    var last = -1
    var byOffset: [Int: Int] = [:]
    let endFrame = aligned(Self.end) ?? totalFrames
    for offset in orderedOffsets {
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
  typealias Position = (frame: Int, precision: Precision)

  func report(bytesPerFrame: Int, totalFrames: Int) -> WireTimingReport {
    WireTimingReport(requestedBookmarks: needsBookmarks, bookmarksReceived: bookmarksReceived,
                     wordsReceived: wordsReceived, wordsMismatched: wordsMismatched,
                     wordStartsUsed: wordFrames(bytesPerFrame: bytesPerFrame, totalFrames: totalFrames).count)
  }

  private func wordFrames(bytesPerFrame: Int, totalFrames: Int) -> [Int: Int] {
    var frames: [Int: Int] = [:], last = -1
    for (offset, byte) in words.sorted(by: { $0.key < $1.key }) {
      let frame = byte / bytesPerFrame
      guard !conflictingWords.contains(offset), byte % bytesPerFrame == 0,
            frame < totalFrames, frame > last, frame > 0 || offset <= (wordStarts.first ?? 0) else { continue }
      frames[offset] = frame
      last = frame
    }
    return frames
  }

  // A later word's first sample cannot be recovered from a marker for some
  // other word. Keep the whole reading if Apple timed the requested positions.
  func recoveryCuts(bytesPerFrame: Int, totalFrames: Int) -> [Int] {
    guard needsTiming, wordStarts.count > 1, bytesPerFrame > 0, totalFrames > 0 else { return [] }
    let exact = nativeFrames(bytesPerFrame: bytesPerFrame, totalFrames: totalFrames)
    let timed = wordFrames(bytesPerFrame: bytesPerFrame, totalFrames: totalFrames)
    var cuts = Set<Int>(), missing = false
    for (mark, named) in zip(marks, exact) where mark.offset > 0 && mark.offset < length {
      let i = Self.firstAtLeast(mark.offset, in: wordStarts)
      let upper = i < wordStarts.count ? wordStarts[i] : nil
      let lower = upper == mark.offset ? upper : (i > 0 ? wordStarts[i - 1] : nil)
      if let lower, lower != wordStarts.first { cuts.insert(lower) }
      if let upper, upper != wordStarts.first { cuts.insert(upper) }
      let expected = mark.after == true ? lower : upper
      if named == nil && timed[mark.offset] == nil && expected.flatMap({ timed[$0] }) == nil { missing = true }
    }
    return missing ? cuts.sorted() : []
  }

  func placements(bytesPerFrame: Int, totalFrames: Int,
                  startsAtWord: Bool = false, endsAtNextWord: Bool = false) -> [Position] {
    guard bytesPerFrame > 0, totalFrames > 0 else { return [] }
    var frames = wordFrames(bytesPerFrame: bytesPerFrame, totalFrames: totalFrames)
    if startsAtWord { frames[0] = 0 }
    if endsAtNextWord { frames[length] = totalFrames }
    let boundaries = frames.sorted { $0.key < $1.key }.map {
      OvWordBoundary(offset: UInt32($0.key), frame: UInt32($0.value))
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
