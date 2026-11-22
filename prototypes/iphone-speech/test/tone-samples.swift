// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

@main enum ToneSamplesTest {
  static func main() {
    for (ms, expected) in [(1, [48]), (480, [23040]), (2475, [48000, 48000, 22800]),
                           (60000, Array(repeating: 48000, count: 60))] {
      let rate = 48000.0, hz = 660.25
      let tone = QueuedTone(hz: hz, milliseconds: ms, sampleRate: rate)
      var offset = 0
      for count in expected {
        precondition(tone.nextFrameCount == count)
        var pcm = [Float](repeating: 0, count: count)
        pcm.withUnsafeMutableBufferPointer { tone.render(into: $0) }
        for index in pcm.indices {
          let t = Double(offset + index) / rate
          let end = Double(ms) / 1000 - 1 / rate
          let gain = max(0, min(1, min(t, end - t) / 0.004))
          let expectedSample = Float(0.15 * gain * sin(t * (2 * .pi * hz)))
          precondition(abs(pcm[index] - expectedSample) < 0.000001)
        }
        offset += count
      }
      precondition(tone.nextFrameCount == 0 && offset == ms * 48)
    }
    print("Passed continuous tone samples, duration, fades and bounded buffer sizes.")
  }
}
