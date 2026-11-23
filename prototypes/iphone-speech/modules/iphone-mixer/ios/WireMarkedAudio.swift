// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later
#if canImport(AVFoundation)
import AVFoundation
#endif
import OmnivoxMobile

// Apple can supply markers after the PCM they describe. Retain at most one
// bounded marked span. Unmarked speech uses the progressive renderer.
final class WireMarkedAudio {
  let original: WireBookmarks
  var timing: WireSpeechTiming, pcmEnded = false
  private var samples: [Float] = []
  private var rate: UInt32 = 0, channels = 0, bytesPerFrame = 0
  private let tones: [WireToneMark]
  init(_ item: WireItem, _ plan: WireBookmarks) {
    original = plan
    timing = WireSpeechTiming(item, plan)
    tones = item.marks ?? []
  }

  #if canImport(AVFoundation)
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
  #endif

  func finishPart() -> WireSpeechTiming.Result? {
    // Some voices finish a formatting space without producing any PCM.
    // Rust still owns the separator's cues, effect tails and playback markers.
    if samples.isEmpty && original.isWhitespaceOnly {
      samples = [0]
      rate = 44100
      channels = 1
      bytesPerFrame = MemoryLayout<Float>.stride
    }
    let result = timing.finish(bytesPerFrame: bytesPerFrame, totalFrames: samples.count / max(1, channels))
    if case let .next(_, discardAudio)? = result {
      if discardAudio {
        samples.removeAll()
        rate = 0
        channels = 0
        bytesPerFrame = 0
      }
      pcmEnded = false
    }
    return result
  }

  func render(_ positions: [WireBookmarks.Position], clock: OpaquePointer, token: OpaquePointer,
              presentation: WirePresentation?) -> (OpaquePointer?, WireTimingReport) {
    var anchors: [OvAnchorFrame] = []
    var report = timing.report
    var reported = Set<Int>()
    for (mark, position) in zip(original.marks, positions) {
      if mark.offset > 0 && mark.offset < original.length && reported.insert(mark.offset).inserted {
        switch position.precision {
        case .exact: report.exact += 1
        case .word: report.word += 1
        case .span: report.span += 1
        }
      }
      let precision: UInt8 = position.precision == .exact ? 0 : position.precision == .word ? 1 : 2
      anchors.append(OvAnchorFrame(frame: UInt32(position.frame), precision: precision))
    }
    if let presentation {
      let pcm = samples.withUnsafeBufferPointer { input in
        anchors.withUnsafeBufferPointer { points in
          ov_ios_render_presentation(presentation.pointer, input.baseAddress, input.count, rate, UInt16(channels),
                                     points.baseAddress, points.count, presentation.token)
        }
      }
      return (pcm, report)
    }
    let cues = zip(tones, anchors).map { tone, point in
      OvToneMark(frame: point.frame, hz: tone.hz, ms: tone.ms, gain: tone.gain, insert: tone.placement == .insert)
    }
    let pcm = samples.withUnsafeBufferPointer { input in
      cues.withUnsafeBufferPointer { points in
        ov_ios_mix_marked(clock, input.baseAddress, input.count, rate, UInt16(channels), points.baseAddress, points.count, token)
      }
    }
    return (pcm, report)
  }
}
