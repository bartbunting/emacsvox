// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later
import AVFoundation
import OmnivoxMobile

final class WireResources {
  let loader: OpaquePointer
  let personal: OpaquePointer
  init?(at url: URL) {
    guard let root = try? CueImport.root(), let imported = ov_ios_loader_new(root.path) else { return nil }
    guard let loader = ov_ios_loader_new(url.path) else { ov_ios_loader_free(imported); return nil }
    personal = imported
    self.loader = loader
  }
  deinit { ov_ios_loader_free(loader); ov_ios_loader_free(personal) }

  func sound(_ id: String, gain: Float, token: OpaquePointer) -> OpaquePointer? {
    if id.hasPrefix("omnivox-icon:personal/"), let pcm = ov_ios_sound(personal, id, gain, token) { return pcm }
    return ov_ios_sound(loader, id, gain, token)
  }
}

final class RenderToken {
  let pointer = ov_ios_token_new()!
  deinit { ov_ios_token_free(pointer) }
}

// Transfer one owned canonical Omnivox buffer into Apple's planar player format.
func wireBuffer(_ pcm: OpaquePointer, format: AVAudioFormat) -> AVAudioPCMBuffer? {
  defer { ov_ios_pcm_free(pcm) }
  let count = ov_ios_frames(pcm)
  guard count > 0, let source = ov_ios_samples(pcm),
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
        let planes = buffer.floatChannelData else { return nil }
  buffer.frameLength = AVAudioFrameCount(count)
  for i in 0..<count {
    planes[0][i] = source[2 * i]
    planes[1][i] = source[2 * i + 1]
  }
  return buffer
}

func wireUtterance(_ item: WireItem, ssml: String? = nil) -> AVSpeechUtterance? {
  guard let words = item.text, !words.isEmpty, let id = item.voice,
        let selected = AVSpeechSynthesisVoice(identifier: id) else { return nil }
  let utterance = ssml.flatMap { AVSpeechUtterance(ssmlRepresentation: $0) } ?? AVSpeechUtterance(string: words)
  utterance.voice = selected
  utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate,
      (item.rate ?? 1) * AVSpeechUtteranceDefaultSpeechRate))
  utterance.pitchMultiplier = item.pitch ?? 1
  utterance.volume = item.gain ?? 1
  return utterance
}

private final class EffectStream {
  let node = AVAudioPlayerNode()
  private let resources: WireResources, format: AVAudioFormat
  private let render = DispatchQueue(label: "org.emacsvox.iphone.effects", qos: .userInitiated)
  private var generation = RenderToken(), scheduled = 0
  private var queue: [(WireItem, (Bool) -> Void)] = []
  init(_ resources: WireResources, format: AVAudioFormat) {
    self.resources = resources
    self.format = format
  }
  func play(_ item: WireItem, done: @escaping (Bool) -> Void) {
    guard queue.count < 4096 else { done(false); return }
    queue.append((item, done))
    fill()
  }
  func stop() {
    ov_ios_cancel(generation.pointer)
    generation = RenderToken()
    scheduled = 0
    queue.removeAll()
    node.stop()
  }
  private func fill() {
    while scheduled < 2, !queue.isEmpty {
      let (item, done) = queue.removeFirst()
      let token = generation
      scheduled += 1
      render.async { [weak self, resources, format] in
        let pcm: OpaquePointer?
        if item.kind == .tone {
          pcm = ov_ios_tone(item.hz ?? 0, item.ms ?? 0, item.gain ?? 1, token.pointer)
        } else {
          let id = item.path ?? ""
          pcm = resources.sound(id, gain: item.gain ?? 1, token: token.pointer)
        }
        let buffer = pcm.flatMap { wireBuffer($0, format: format) }
        DispatchQueue.main.async { [weak self] in
          guard let self, self.generation === token else { return }
          let finish: (Bool) -> Void = { [weak self] ok in
            guard let self, self.generation === token else { return }
            self.scheduled -= 1
            done(ok)
            self.fill()
          }
          guard let buffer else { finish(false); return }
          self.node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in
            DispatchQueue.main.async { finish(true) }
          }
          if !self.node.isPlaying { self.node.play() }
        }
      }
    }
  }
}

final class WireAudio: NSObject, WireOutput, AVSpeechSynthesizerDelegate {
  private let synth = AVSpeechSynthesizer(), engine = AVAudioEngine()
  private let bufferSynth = AVSpeechSynthesizer()
  private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
  private var available: [AVAudioPlayerNode] = []
  private var playing: [ObjectIdentifier: (WirePlayback<AVAudioPCMBuffer>, WireMixer, AVAudioPlayerNode)] = [:]
  private let tones: EffectStream, sounds: EffectStream, inserts: EffectStream
  private var speech: AVSpeechUtterance?, spoken: ((Bool) -> Void)?, pause: DispatchWorkItem?
  var interrupted: (() -> Void)?
  var resolvedMarks: ((WireTimingReport) -> Void)?
  private var observers: [NSObjectProtocol] = []

  init(_ resources: WireResources) {
    tones = EffectStream(resources, format: format)
    sounds = EffectStream(resources, format: format)
    inserts = EffectStream(resources, format: format)
    super.init()
    synth.delegate = self
    synth.usesApplicationAudioSession = false
    available = [AVAudioPlayerNode()]
    for node in [tones.node, sounds.node, inserts.node] + available {
      engine.attach(node)
      engine.connect(node, to: engine.mainMixerNode, format: format)
    }
    observers.append(NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
      object: engine, queue: .main) { [weak self] _ in self?.interrupted?() })
    observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification,
      object: nil, queue: .main) { [weak self] note in
        if (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue {
          self?.interrupted?()
        }
      })
  }

  deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) } }

  private func startAudio() throws {
    if !engine.isRunning {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
      try session.setActive(true)
      try engine.start()
    }
  }

  func playMixed(_ items: ArraySlice<WireItem>, holdTail: @escaping () -> () -> Void, done: @escaping (Int, Bool) -> Void) {
    do { try startAudio() } catch { done(0, true); return }
    // A previous dispatch may still own this lane's overlay tail.
    let node: AVAudioPlayerNode
    if let idle = available.popLast() { node = idle }
    else {
      node = AVAudioPlayerNode()
      engine.attach(node)
      engine.connect(node, to: engine.mainMixerNode, format: format)
    }
    let key = ObjectIdentifier(node)
    let mixer = WireMixer(format: format, synth: bufferSynth, resolvedMarks: resolvedMarks)
    let playback = WirePlayback<AVAudioPCMBuffer>(items, speech: mixer.speech, flush: mixer.flush,
      enqueue: { buffer, played in
        node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in
          DispatchQueue.main.async { mixer.played(Int(buffer.frameLength)); played() }
        }
        if !node.isPlaying { node.play() }
      }, holdTail: holdTail, done: done, release: { [weak self] in
        self?.playing.removeValue(forKey: key)
        node.stop()
        self?.available.append(node)
      })
    playing[key] = (playback, mixer, node)
    playback.advance()
  }

  func play(_ item: WireItem, done: @escaping (Bool) -> Void) {
    switch item.kind {
    case .speech:
      guard !(item.text ?? "").isEmpty else { done(true); return }
      guard let utterance = wireUtterance(item) else { done(false); return }
      speech = utterance
      spoken = done
      synth.speak(utterance)
    case .silence:
      let task = DispatchWorkItem(block: { done(true) })
      pause = task
      DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Int(item.ms ?? 0)), execute: task)
    case .sound, .tone:
      do {
        try startAudio()
        let stream: EffectStream
        switch item.placement {
        case .independent: stream = tones
        case .insert: stream = inserts
        case .overlay, nil: stream = sounds
        }
        stream.play(item, done: done)
      } catch { done(false) }
    }
  }
  func stop(all: Bool) {
    for (playback, mixer, node) in playing.values {
      playback.stop()
      mixer.cancel()
      node.stop()
      available.append(node)
    }
    playing.removeAll()
    speech = nil
    spoken = nil
    pause?.cancel()
    pause = nil
    synth.stopSpeaking(at: .immediate)
    inserts.stop()
    if all { tones.stop(); sounds.stop() }
  }
  private func finish(_ utterance: AVSpeechUtterance, played: Bool) {
    DispatchQueue.main.async { [weak self] in
      guard let self, self.speech === utterance else { return }
      self.speech = nil
      let done = self.spoken
      self.spoken = nil
      done?(played)
    }
  }
  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    finish(utterance, played: true)
  }
  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
    finish(utterance, played: false)
  }
}
