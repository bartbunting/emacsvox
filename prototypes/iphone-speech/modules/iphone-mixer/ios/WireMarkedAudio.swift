// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later
import AVFoundation
import OmnivoxMobile

// Apple can supply markers after the PCM they describe. Retain at most one
// bounded marked span. Unmarked speech uses the progressive renderer.
final class WireMarkedAudio {
  var plan: WireBookmarks, pcmEnded = false
  private var samples: [Float] = []
  private var rate: UInt32 = 0, channels = 0, bytesPerFrame = 0
  init(_ plan: WireBookmarks) { self.plan = plan }

  func append(_ buffer: AVAudioPCMBuffer, stride: Int) -> Bool {
    let frames = Int(buffer.frameLength), nextRate = UInt32(buffer.format.sampleRate)
    let nextChannels = Int(buffer.format.channelCount)
    guard !pcmEnded, stride > 0, (1...2).contains(nextChannels), let planes = buffer.floatChannelData,
          rate == 0 || (rate == nextRate && channels == nextChannels && bytesPerFrame == stride),
          Int64(samples.count) + Int64(frames * nextChannels) <= min(16 * 1024 * 1024, Int64(nextRate) * 120 * Int64(nextChannels))
    else { return false }
    rate = nextRate
    channels = nextChannels
    bytesPerFrame = stride
    if channels == 1 {
      samples.append(contentsOf: UnsafeBufferPointer(start: planes[0], count: frames))
    } else {
      for i in 0..<frames { samples.append(planes[0][i]); samples.append(planes[1][i]) }
    }
    return true
  }

  func render(clock: OpaquePointer, token: OpaquePointer) -> (OpaquePointer?, Int, Int) {
    let positions = plan.nativeFrames(bytesPerFrame: bytesPerFrame, totalFrames: samples.count / max(1, channels))
    var cues: [OvToneMark] = []
    var interior = 0, exact = 0
    for (mark, frame) in zip(plan.marks, positions) {
      let inside = mark.offset > 0 && mark.offset < plan.length
      if inside { interior += 1 }
      guard let frame else { continue }
      if inside { exact += 1 }
      cues.append(OvToneMark(frame: UInt32(frame), hz: mark.hz, ms: mark.ms, gain: mark.gain, insert: mark.placement == .insert))
    }
    let pcm = samples.withUnsafeBufferPointer { input in
      cues.withUnsafeBufferPointer { points in
        ov_ios_mix_marked(clock, input.baseAddress, input.count, rate, UInt16(channels), points.baseAddress, points.count, token)
      }
    }
    return (pcm, pcm == nil ? 0 : exact, interior)
  }
}
