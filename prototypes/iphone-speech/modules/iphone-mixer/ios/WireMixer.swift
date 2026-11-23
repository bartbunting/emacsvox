// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later
import AVFoundation
import OmnivoxMobile

// One Rust renderer per presentation. Its serial queue owns the resampler,
// pending cues and overlay carry. Apple callbacks lend PCM only until return.
final class WireMixer {
  typealias Packet = WirePlayback<AVAudioPCMBuffer>.Packet
  private let clock = ov_ios_mix_new()!, token = RenderToken()
  private let work = DispatchQueue(label: "org.emacsvox.iphone.presentation", qos: .userInitiated)
  private let format: AVAudioFormat, synth: AVSpeechSynthesizer
  private let resolvedMarks: ((WireTimingReport) -> Void)?
  private let reached: ((String) -> Void)?
  private let presentation: WirePresentation?
  private var markers: [ObjectIdentifier: [String]] = [:]
  private var current: Capture?
  private let capacity = NSCondition()
  private var queuedFrames = 0, pendingInputBytes = 0, cancelled = false

  private final class Capture {
    var deadline = ProcessInfo.processInfo.systemUptime + 3   // main queue
    var inputFull = false                                     // main queue
    var ended = false                                         // render queue
    var startMarker: String?                                  // render queue
    var marked: WireMarkedAudio?                              // render queue
    let audio: (Packet) -> Void, finished: (Bool) -> Void
    init(_ audio: @escaping (Packet) -> Void, _ finished: @escaping (Bool) -> Void) {
      self.audio = audio
      self.finished = finished
    }
  }

  init(format: AVAudioFormat, synth: AVSpeechSynthesizer, resolvedMarks: ((WireTimingReport) -> Void)?, presentation: WirePresentation? = nil, reached: ((String) -> Void)? = nil) {
    self.reached = reached
    self.presentation = presentation
    self.format = format
    self.synth = synth
    self.resolvedMarks = resolvedMarks
  }
  deinit { ov_ios_mix_free(clock) }

  func cancel() {
    markers.removeAll()
    ov_ios_cancel(token.pointer)
    wakeProducer()
    if current != nil {
      current = nil
      synth.stopSpeaking(at: .immediate)
    }
  }

  private func wakeProducer() {
    capacity.lock()
    cancelled = true
    capacity.broadcast()
    capacity.unlock()
  }

  func played(_ buffer: AVAudioPCMBuffer) {
    if let lines = markers.removeValue(forKey: ObjectIdentifier(buffer)) {
      if let presentation { presentation.reached(lines) }
      else { for line in lines { reached?(line) } }
    }
    let frames = Int(buffer.frameLength)
    capacity.lock()
    queuedFrames = max(0, queuedFrames - frames)
    capacity.signal()
    capacity.unlock()
  }

  private func reserve(_ frames: Int, mayWait: Bool) -> Bool {
    capacity.lock()
    defer { capacity.unlock() }
    // Keep producer threads close to playback. A system voice that calls
    // on the UI thread must leave it free for Stop and playback callbacks.
    while mayWait && queuedFrames >= 88200 && !cancelled { capacity.wait() }
    guard !cancelled, queuedFrames < 120 * 44100 else { return false }
    queuedFrames += frames
    return true
  }

  private func tones(_ items: [WireItem]) -> Bool {
    items.allSatisfy {
      ov_ios_mix_tone(clock, $0.placement == .insert, $0.hz ?? 0, $0.ms ?? 0, $0.gain ?? 1, token.pointer)
    }
  }

  func speech(_ cues: [WireItem], _ item: WireItem, _ audio: @escaping (Packet) -> Void,
              _ finished: @escaping (Bool) -> Void) {
    let bookmarks = WireBookmarks(item)
    guard presentation == nil || bookmarks != nil else { finished(false); return }
    guard let utterance = wireUtterance(item, ssml: bookmarks?.needsBookmarks == true ? bookmarks?.ssml : nil) else { finished(false); return }
    let capture = Capture(audio, finished)
    capture.startMarker = item.startMarker
    capture.marked = bookmarks.map { WireMarkedAudio($0, tones: item.marks ?? []) }
    current = capture
    work.async {
      let ready = self.tones(cues)
      DispatchQueue.main.async {
        guard self.current === capture else { return }
        guard ready else { self.end(capture, ok: false); return }
        capture.deadline = ProcessInfo.processInfo.systemUptime + 3
        self.watch(capture)
        let collect: AVSpeechSynthesizer.BufferCallback = { [weak self, weak capture] buffer in
          guard let self, let capture else { return }
          let stride = Int((buffer as? AVAudioPCMBuffer)?.format.streamDescription.pointee.mBytesPerFrame ?? 0)
          // The system chooses its callback queue. A callback on main must
          // never wait behind a producer throttled by hardware playback.
          if Thread.isMainThread {
            guard self.current === capture, !capture.inputFull else { return }
            let pcm = buffer as? AVAudioPCMBuffer
            let bytes = Int(pcm?.frameLength ?? 0) * Int(pcm?.format.channelCount ?? 0) * 4
            self.capacity.lock()
            capture.inputFull = bytes > 64 * 1024 * 1024 - self.pendingInputBytes
            if !capture.inputFull { self.pendingInputBytes += bytes }
            self.capacity.unlock()
            if capture.inputFull {
              self.work.async { _ = self.post(nil, capture, end: true) }
            } else {
              let samples = Result { try IphoneMixerModule.copySamples(buffer) }
              self.work.async {
                self.receive(samples, capture, stride: stride)
                self.capacity.lock()
                self.pendingInputBytes -= bytes
                self.capacity.unlock()
              }
            }
          } else {
            self.work.sync { self.receive(Result { try IphoneMixerModule.copySamples(buffer) }, capture, stride: stride) }
          }
        }
        if let bookmarks, bookmarks.needsBookmarks {
          let useWords = bookmarks.acceptsWordRanges(in: utterance.speechString)
          self.synth.write(utterance, toBufferCallback: collect, toMarkerCallback: { [weak self, weak capture] markers in
            guard let self, let capture else { return }
            let names: [(String, Int)]
            let words = useWords ? Array(markers.lazy.filter { $0.mark == .word }.prefix(4096).map { ($0.textRange, $0.byteSampleOffset) }) : []
            if #available(iOS 17.0, *) {
              names = Array(markers.lazy.filter { $0.mark == .bookmark }.prefix(513).map { ($0.bookmarkName, $0.byteSampleOffset) })
            } else { names = [] }
            self.work.async {
              guard !capture.ended, let marked = capture.marked else { return }
              for (name, byte) in names { marked.plan.observe(name, byte: byte) }
              for (range, byte) in words { marked.plan.observeWord(range, byte: byte) }
              if marked.pcmEnded && marked.plan.complete { self.finishMarked(capture, marked) }
            }
          })
        } else {
          self.synth.write(utterance, toBufferCallback: collect)
        }
      }
    }
  }

  private func watch(_ capture: Capture) {
    let remaining = capture.deadline - ProcessInfo.processInfo.systemUptime
    if remaining <= 0 { end(capture, ok: false); return }
    DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak self, weak capture] in
      guard let self, let capture, self.current === capture else { return }
      self.watch(capture)
    }
  }

  private func end(_ capture: Capture, ok: Bool) {
    guard current === capture else { return }
    current = nil
    if !ok { wakeProducer(); synth.stopSpeaking(at: .immediate) }
    capture.finished(ok)
  }

  private func post(_ pcm: OpaquePointer?, _ capture: Capture, end: Bool, mayWait: Bool = false) -> Bool {
    var packets: [(AVAudioPCMBuffer, String?)] = []
    var valid = false
    if let pcm {
      defer { ov_ios_pcm_free(pcm) }
      let frames = ov_ios_frames(pcm)
      if frames == 0 { valid = true }
      else if reserve(frames, mayWait: mayWait) {
        if let line = capture.startMarker {
          if let initial = wireBufferSlice(pcm, format: format, frames: 0..<1) {
            packets.append((initial, line))
            capture.startMarker = nil
            if frames == 1 { valid = true }
            else if let rest = wireBufferSlice(pcm, format: format, frames: 1..<frames) {
              packets.append((rest, nil))
              valid = true
            }
          }
        } else if let buffer = wireBufferSlice(pcm, format: format, frames: 0..<frames) {
          packets.append((buffer, nil))
          valid = true
        }
      }
    }
    if end || !valid { capture.ended = true }
    DispatchQueue.main.async { [weak self, weak capture, packets, valid] in
      guard let self, let capture, self.current === capture else { return }
      self.capacity.lock()
      let lead = Double(self.queuedFrames) / 44100
      self.capacity.unlock()
      capture.deadline = ProcessInfo.processInfo.systemUptime + lead + 3
      if valid {
        for (buffer, line) in packets {
          if let line { self.markers[ObjectIdentifier(buffer)] = [line] }
          capture.audio((buffer, Int(buffer.frameLength)))
        }
      }
      if end || !valid { self.end(capture, ok: valid) }
    }
    return valid
  }

  private func finishMarked(_ capture: Capture, _ marked: WireMarkedAudio) {
    guard !capture.ended else { return }
    let (pcm, report) = marked.render(clock: clock, token: token.pointer, presentation: presentation)
    DispatchQueue.main.async { [weak self, weak capture] in
      guard let self, let capture, self.current === capture else { return }
      self.resolvedMarks?(report)
    }
    if let presentation, let pcm {
      defer { ov_ios_pcm_free(pcm) }
      guard let regions = presentation.regions(frames: ov_ios_frames(pcm)) else { _ = post(nil, capture, end: true); return }
      for region in regions {
        var start = region.frames.lowerBound
        while start < region.frames.upperBound {
          let end = min(start + 16384, region.frames.upperBound)
          guard let buffer = wireBufferSlice(pcm, format: format, frames: start..<end), reserve(end - start, mayWait: true)
          else { _ = post(nil, capture, end: true); return }
          let lines = end == region.frames.upperBound ? region.events : []
          DispatchQueue.main.async { [weak self, weak capture] in
            guard let self, let capture, self.current === capture else { return }
            if !lines.isEmpty { self.markers[ObjectIdentifier(buffer)] = lines }
            capture.deadline = ProcessInfo.processInfo.systemUptime + 3
            capture.audio((buffer, Int(buffer.frameLength)))
          }
          start = end
        }
      }
      capture.ended = true
      DispatchQueue.main.async { self.end(capture, ok: true) }
    } else {
      _ = post(pcm, capture, end: true, mayWait: true)
    }
  }

  private func receive(_ input: Result<AVAudioPCMBuffer?, Error>, _ capture: Capture, stride bytesPerFrame: Int) {
    guard !capture.ended else { return }
    do {
      let samples = try input.get()
      if let marked = capture.marked {
        if let samples {
          if !marked.append(samples, stride: bytesPerFrame) { _ = post(nil, capture, end: true) }
        } else {
          marked.pcmEnded = true
          if marked.plan.complete { finishMarked(capture, marked) }
          else {
            // Allow outstanding metadata callbacks to arrive. Only reported
            // audio offsets determine placement, including on expiry.
            work.asyncAfter(deadline: .now() + .milliseconds(150)) { self.finishMarked(capture, marked) }
          }
        }
        return
      }
      guard let samples else {
        _ = post(ov_ios_mix_speech(clock, nil, 0, 0, 0, true, token.pointer), capture, end: true, mayWait: true)
        return
      }
      let channels = Int(samples.format.channelCount), rate = UInt32(samples.format.sampleRate)
      guard let planes = samples.floatChannelData else { _ = post(nil, capture, end: true); return }
      let frames = Int(samples.frameLength)
      // Bound each conversion even if the voice delivers its whole utterance
      // in one callback. Mono can be borrowed directly.
      for first in stride(from: 0, to: frames, by: 8192) {
        let count = min(8192, frames - first)
        let pcm: OpaquePointer?
        if channels == 1 {
          pcm = ov_ios_mix_speech(clock, planes[0] + first, count, rate, 1, false, token.pointer)
        } else {
          var stereo = [Float](repeating: 0, count: count * 2)
          for i in 0..<count {
            stereo[2 * i] = planes[0][first + i]
            stereo[2 * i + 1] = planes[1][first + i]
          }
          pcm = stereo.withUnsafeBufferPointer {
            ov_ios_mix_speech(clock, $0.baseAddress, $0.count, rate, 2, false, token.pointer)
          }
        }
        if !post(pcm, capture, end: false, mayWait: true) { return }
      }
    } catch { _ = post(nil, capture, end: true) }
  }

  func flush(_ trailing: [WireItem]?, _ done: @escaping (Packet?, Packet?, Bool) -> Void) {
    work.async {
      if let presentation = self.presentation {
        let pcm = ov_ios_presentation_tail(presentation.pointer)
        let buffer = pcm.flatMap { wireBuffer($0, format: self.format) }
        let valid = trailing != nil && (pcm == nil || buffer != nil)
        DispatchQueue.main.async { done(nil, buffer.map { ($0, Int($0.frameLength)) }, valid) }
        return
      }
      let ready = trailing.map(self.tones) ?? true
      var tail: OpaquePointer?
      let primary = ov_ios_mix_finish(self.clock, trailing != nil && ready, &tail, self.token.pointer)
      let bodyFrames = primary.map { ov_ios_frames($0) }
      let tailFrames = tail.map { ov_ios_frames($0) } ?? 0
      let body = primary.flatMap { wireBuffer($0, format: self.format) }
      let rest = tail.flatMap { wireBuffer($0, format: self.format) }
      let valid = ready && bodyFrames != nil && (bodyFrames == 0 || body != nil) && (tailFrames == 0 || rest != nil)
      DispatchQueue.main.async {
        done(body.map { ($0, Int($0.frameLength)) }, rest.map { ($0, Int($0.frameLength)) }, valid)
      }
    }
  }
}
