// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

// Keep one Omnivox speech window even when the system voice omits timings.
// Measure the starts of the affected words by collecting their actual audio.
struct WireSpeechTiming {
  enum Result {
    case next(WireItem, discardAudio: Bool)
    case ready([WireBookmarks.Position])
  }

  private let item: WireItem, original: WireBookmarks
  var plan: WireBookmarks
  private(set) var report = WireTimingReport()
  private var ranges: [Range<Int>] = [], part = 0, firstFrame = 0
  private var indicesByPart: [[Int]] = [], positions: [WireBookmarks.Position] = []

  init(_ item: WireItem, _ plan: WireBookmarks) {
    self.item = item
    original = plan
    self.plan = plan
  }

  private mutating func nextPart(discardAudio: Bool) -> Result {
    let range = ranges[part], bytes = item.text!.utf8
    var slice = item
    let low = bytes.index(bytes.startIndex, offsetBy: range.lowerBound)
    let high = bytes.index(low, offsetBy: range.count)
    slice.text = String(decoding: bytes[low..<high], as: UTF8.self)
    slice.marks = nil
    slice.anchors = indicesByPart[part].map {
      let mark = original.marks[$0]
      return WireAnchor(offset: mark.offset - range.lowerBound, after: mark.after)
    }
    // All cuts are Unicode word boundaries and all original anchors were validated.
    plan = WireBookmarks(slice)!
    return .next(slice, discardAudio: discardAudio)
  }

  mutating func finish(bytesPerFrame: Int, totalFrames: Int) -> Result? {
    guard bytesPerFrame > 0, totalFrames > firstFrame else { return nil }
    if ranges.isEmpty {
      report = plan.report(bytesPerFrame: bytesPerFrame, totalFrames: totalFrames)
      let cuts = plan.recoveryCuts(bytesPerFrame: bytesPerFrame, totalFrames: totalFrames)
      guard !cuts.isEmpty else {
        return .ready(plan.placements(bytesPerFrame: bytesPerFrame, totalFrames: totalFrames))
      }
      let edges = [0] + cuts + [original.length]
      report.measuredWords = true
      ranges = zip(edges, edges.dropFirst()).map { $0..<$1 }
      // A cut belongs to the following word. Keep all actions at the same
      // offset in their original order, including actions at the span end.
      indicesByPart = Array(repeating: [], count: ranges.count)
      for (index, mark) in original.marks.enumerated() {
        let part = WireBookmarks.firstAtLeast(mark.offset + 1, in: cuts)
        indicesByPart[part].append(index)
      }
      positions = Array(repeating: (0, .span), count: original.marks.count)
      return nextPart(discardAudio: true)
    }
    let range = ranges[part]
    let local = plan.placements(bytesPerFrame: bytesPerFrame, totalFrames: totalFrames - firstFrame,
                                startsAtWord: part > 0, endsAtNextWord: part + 1 < ranges.count)
    for (index, position) in zip(indicesByPart[part], local) {
      let measuredStart = part > 0 && original.marks[index].offset == range.lowerBound
      positions[index] = (firstFrame + position.frame, measuredStart ? .word : position.precision)
    }
    part += 1
    guard part < ranges.count else { return .ready(positions) }
    firstFrame = totalFrames
    return nextPart(discardAudio: false)
  }
}
