// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

@main enum BookmarkTimings {
  @inline(never) static func prepare(_ item: WireItem) -> Int {
    let plan = WireBookmarks(item)!
    return plan.length + (plan.complete ? 1 : 0) + (plan.needsBookmarks ? plan.ssml.utf8.count : 0)
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
  }
}
