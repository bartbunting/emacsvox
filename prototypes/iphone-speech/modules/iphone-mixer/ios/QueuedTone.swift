// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

final class QueuedTone {
  private let hz: Double
  private let sampleRate: Double
  private let frames: Int
  private var cursor = 0

  init(hz: Double, milliseconds: Int, sampleRate: Double) {
    self.hz = hz
    self.sampleRate = sampleRate
    frames = Int(sampleRate * Double(milliseconds) / 1000)
  }

  // A short cue fits in one buffer. Long tones use bounded lookahead.
  var nextFrameCount: Int { min(Int(sampleRate), frames - cursor) }

  func render(into samples: UnsafeMutableBufferPointer<Float>) {
    precondition(samples.count == nextFrameCount)
    for index in samples.indices {
      let position = cursor + index
      let edge = min(1.0, Double(min(position, frames - position - 1)) / (sampleRate * 0.004))
      samples[index] = Float(0.15 * edge * sin(2 * .pi * hz * Double(position) / sampleRate))
    }
    cursor += samples.count
  }
}
