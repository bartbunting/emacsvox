// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

@main enum BookmarkTimings {
  @inline(never) static func prepare(_ item: WireItem) -> Int {
    let plan = WireBookmarks(item)!
    return plan.length + (plan.complete ? 1 : 0) + (plan.needsBookmarks ? plan.ssml.utf8.count : 0)
  }

  // Fixed sample lengths exercise timing bookkeeping without a synthesizer or audio device.
  @inline(never) static func recover(_ item: WireItem, nativeMarks: Bool) -> Int {
    var plan = WireBookmarks(item)!
    if nativeMarks {
      for mark in plan.marks { plan.observe("ov-\(mark.offset)", byte: mark.offset * 4) }
      plan.observe(WireBookmarks.end, byte: plan.length * 4)
    }
    var timing = WireSpeechTiming(item, plan), frames = plan.length
    while let result = timing.finish(bytesPerFrame: 4, totalFrames: frames) {
      switch result {
      case let .next(piece, discard):
        frames = (discard ? 0 : frames) + piece.text!.utf8.count
      case let .ready(positions):
        precondition(positions.count == plan.marks.count)
        return positions.reduce(0) { $0 &+ $1.frame }
      }
    }
    preconditionFailure("Timing a nonempty line failed")
  }

  static func main() {
    let line = "Read the selected line with the same voice."
    let long = String(repeating: line + " ", count: 24)
    let fixtures: [(String, String, [Int])] = [
      ("plain line", line, []), ("long line", long, []),
      ("indent tone", line, [0]), ("word tone", line, [9]),
      ("in-word tone", line, [11])
    ]
    for (label, text, offsets) in fixtures {
      let item = WireItem(kind: .speech, text: text, rate: 1.5, pitch: 1, gain: 1,
                          anchors: offsets.map { WireAnchor(offset: $0) })
      var checksum = prepare(item), times = [Double]()
      let iterations = 120
      for _ in 0..<21 {
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<iterations { checksum &+= prepare(item) }
        times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / Double(iterations) / 1000)
      }
      times.sort()
      print(String(format: "%@, median %.2f µs, p95 %.2f µs, checksum %d", label, times[10], times[19], checksum))
    }
    let word = "échoCase ", count = 256
    let anchors = (0..<count).flatMap { i in
      [WireAnchor(offset: i * word.utf8.count), WireAnchor(offset: i * word.utf8.count + 5, after: true)]
    }
    let item = WireItem(kind: .speech, text: String(repeating: word, count: count), anchors: anchors)
    for native in [true, false] {
      var times = [Double](), checksum = 0
      for _ in 0..<21 {
        let start = DispatchTime.now().uptimeNanoseconds
        checksum &+= recover(item, nativeMarks: native)
        times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1000)
      }
      times.sort()
      print(String(format: "512 cues, %@, median %.2f µs, p95 %.2f µs, checksum %d",
                   native ? "native marks" : "word recovery", times[10], times[19], checksum))
    }
  }
}
