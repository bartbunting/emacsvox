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
  private let trace: WireSpeechTrace, lane: String
  private let resolvedMarks: ((WireTimingReport) -> Void)?
  private let reached: ((String) -> Void)?
  private let presentation: WirePresentation?
  private let voiceLookup: (String) -> AVSpeechSynthesisVoice?
  private var markers: [ObjectIdentifier: [String]] = [:]
  private var current: Capture?
  private let capacity = NSCondition()
  private var queuedFrames = 0, pendingInputBytes = 0, cancelled = false

  private final class Capture {
    let ticket: WireSpeechTrace.Ticket?
    var level = WireTraceLevel(), inputFrames = 0, inputBuffers = 0 // render queue
    var deadline = ProcessInfo.processInfo.systemUptime + 3   // main queue
    var inputFull = false                                     // main queue
    var writingPart = 0                                       // main queue
    var ended = false                                         // render queue
    var part = 0                                              // render queue
    var startMarker: String?                                  // render queue
    var marked: WireMarkedAudio?                              // render queue
    let audio: (Packet) -> Void, finished: (Bool) -> Void
    init(_ ticket: WireSpeechTrace.Ticket?, _ audio: @escaping (Packet) -> Void, _ finished: @escaping (Bool) -> Void) {
      self.ticket = ticket
      self.audio = audio
      self.finished = finished
    }
  }

  init(format: AVAudioFormat, synth: AVSpeechSynthesizer, trace: WireSpeechTrace, lane: String, loudness: UInt8,
       resolvedMarks: ((WireTimingReport) -> Void)?, presentation: WirePresentation? = nil, voices: [String: AVSpeechSynthesisVoice]? = nil, reached: ((String) -> Void)? = nil) {
    self.trace = trace
    self.lane = lane
    self.reached = reached
    self.presentation = presentation
    if let voices { voiceLookup = { voices[$0] } }
    else { voiceLookup = { AVSpeechSynthesisVoice(identifier: $0) } }
    self.format = format
    self.synth = synth
    self.resolvedMarks = resolvedMarks
    if let presentation { ov_ios_presentation_set_loudness(presentation.pointer, loudness) }
    else { ov_ios_mix_set_loudness(clock, loudness) }
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
      $0.queueTone(clock, token: token.pointer)
    }
  }

  func speech(_ cues: [WireItem], _ item: WireItem, _ audio: @escaping (Packet) -> Void,
              _ finished: @escaping (Bool) -> Void) {
    guard item.unavailable != true else { finished(false); return }
    let bookmarks = WireBookmarks(item)
    guard presentation == nil || bookmarks != nil else { finished(false); return }
    let ticket = trace.begin("\(lane) \(presentation == nil ? "queued PCM" : "timeline PCM") voice \(item.voice ?? "") gain \(item.gain ?? 1) text \((item.text ?? "").debugDescription)")
    let capture = Capture(ticket, audio, finished)
    capture.startMarker = item.startMarker
    capture.marked = bookmarks.map { WireMarkedAudio(item, $0) }
    current = capture
    work.async {
      let ready = (self.presentation != nil || item.beginVoice(self.clock)) && self.tones(cues)
      DispatchQueue.main.async {
        guard self.current === capture else { return }
        guard ready else { self.end(capture, ok: false); return }
        capture.deadline = ProcessInfo.processInfo.systemUptime + 3
        self.watch(capture)
        self.write(item, bookmarks: bookmarks, capture: capture, part: 0)
      }
    }
  }

  private func write(_ item: WireItem, bookmarks: WireBookmarks?, capture: Capture, part: Int) {
    guard current === capture else { return }
    guard let utterance = wireUtterance(item, ssml: bookmarks?.needsBookmarks == true ? bookmarks?.ssml : nil,
                                       mixed: true, lookup: voiceLookup)
    else { end(capture, ok: false); return }
    let ticket = capture.ticket
    trace.append(ticket, "Part \(part), requested anchors \(bookmarks?.marks.map(\.offset) ?? []), SSML \(bookmarks?.needsBookmarks == true). Apple speechString \(utterance.speechString.debugDescription)")
    if let bookmarks, bookmarks.needsBookmarks { trace.append(ticket, "SSML request \(bookmarks.ssml.debugDescription)") }
    capture.writingPart = part
    capture.deadline = ProcessInfo.processInfo.systemUptime + 3
    let collect: AVSpeechSynthesizer.BufferCallback = { [weak self, weak capture] buffer in
      guard let self, let capture else { return }
      let pcm = buffer as? AVAudioPCMBuffer
      let stride = Int(pcm?.format.streamDescription.pointee.mBytesPerFrame ?? 0)
      // Apple can deliver PCM on main. Leave that queue free for Stop.
      if Thread.isMainThread {
        guard self.current === capture, capture.writingPart == part, !capture.inputFull else { return }
        let bytes = Int(pcm?.frameLength ?? 0) * Int(pcm?.format.channelCount ?? 0) * 4
        self.capacity.lock()
        capture.inputFull = bytes > 64 * 1024 * 1024 - self.pendingInputBytes
        if !capture.inputFull { self.pendingInputBytes += bytes }
        self.capacity.unlock()
        if capture.inputFull {
          self.work.async { if capture.part == part { _ = self.post(nil, capture, end: true) } }
        } else {
          let samples = Result { try IphoneMixerModule.copySamples(buffer) }
          self.work.async {
            if capture.part == part { self.receive(samples, capture, stride: stride) }
            self.capacity.lock()
            self.pendingInputBytes -= bytes
            self.capacity.unlock()
          }
        }
      } else {
        self.work.sync {
          if capture.part == part { self.receive(Result { try IphoneMixerModule.copySamples(buffer) }, capture, stride: stride) }
        }
      }
    }
    guard let bookmarks, bookmarks.needsTiming else { synth.write(utterance, toBufferCallback: collect); return }
    let useWords = bookmarks.acceptsWordRanges(in: utterance.speechString)
    synth.write(utterance, toBufferCallback: collect, toMarkerCallback: { [weak self, weak capture] markers in
      guard let self, let capture else { return }
      let names: [(String, Int)]
      let words = markers.lazy.filter { $0.mark == .word }.prefix(4096).map { ($0.textRange, $0.byteSampleOffset) }
      if #available(iOS 17.0, *) {
        names = Array(markers.lazy.filter { $0.mark == .bookmark }.prefix(513).map { ($0.bookmarkName, $0.byteSampleOffset) })
      } else { names = [] }
      let ranges = Array(words)
      self.trace.append(ticket, "Named bookmarks and audio bytes \(names). Word UTF-16 ranges and audio bytes \(ranges). Text indices match \(useWords).")
      self.work.async {
        guard !capture.ended, capture.part == part, let marked = capture.marked else { return }
        for (name, byte) in names { marked.timing.plan.observe(name, byte: byte) }
        for (range, byte) in ranges { marked.timing.plan.observeWord(range, byte: byte, matchesSource: useWords) }
        if marked.pcmEnded && marked.timing.plan.complete { self.finishMarked(capture, marked) }
      }
    })
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
        measure(pcm, capture)
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
    if end || !valid { capture.ended = true; reportLevel(capture) }
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

  private func measure(_ pcm: OpaquePointer, _ capture: Capture) {
    guard capture.ticket != nil, let samples = ov_ios_samples(pcm) else { return }
    capture.level.observe(UnsafeBufferPointer(start: samples, count: ov_ios_frames(pcm) * 2))
  }

  private func reportLevel(_ capture: Capture) {
    trace.append(capture.ticket, "Apple input \(capture.inputFrames) frames in \(capture.inputBuffers) buffers. Mixer output \(capture.level.samples / 2) stereo frames, peak \(capture.level.peak), RMS \(capture.level.rms), full-scale samples \(capture.level.fullScale).")
  }

  private func finishMarked(_ capture: Capture, _ marked: WireMarkedAudio) {
    guard !capture.ended else { return }
    guard let result = marked.finishPart() else { _ = post(nil, capture, end: true); return }
    let positions: [WireBookmarks.Position]
    switch result {
    case let .ready(points): positions = points
    case let .next(item, _):
      capture.part += 1
      let part = capture.part, plan = marked.timing.plan
      DispatchQueue.main.async { self.write(item, bookmarks: plan, capture: capture, part: part) }
      return
    }
    let (pcm, report) = marked.render(positions, clock: clock, token: token.pointer, presentation: presentation)
    DispatchQueue.main.async { [weak self, weak capture] in
      guard let self, let capture, self.current === capture else { return }
      self.resolvedMarks?(report)
    }
    if let presentation, let pcm {
      defer { ov_ios_pcm_free(pcm) }
      guard let regions = presentation.regions(frames: ov_ios_frames(pcm)) else { _ = post(nil, capture, end: true); return }
      measure(pcm, capture)
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
      reportLevel(capture)
      DispatchQueue.main.async { self.end(capture, ok: true) }
    } else {
      _ = post(pcm, capture, end: true, mayWait: true)
    }
  }

  private func receive(_ input: Result<AVAudioPCMBuffer?, Error>, _ capture: Capture, stride bytesPerFrame: Int) {
    guard !capture.ended else { return }
    do {
      let samples = try input.get()
      if capture.ticket != nil, let samples {
        capture.inputBuffers += 1
        capture.inputFrames += Int(samples.frameLength)
      }
      if let marked = capture.marked {
        if let samples {
          if !marked.append(samples, stride: bytesPerFrame) { _ = post(nil, capture, end: true) }
        } else {
          marked.pcmEnded = true
          if marked.timing.plan.complete { finishMarked(capture, marked) }
          else {
            let part = capture.part
            work.asyncAfter(deadline: .now() + .milliseconds(150)) {
              if capture.part == part { self.finishMarked(capture, marked) }
            }
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
