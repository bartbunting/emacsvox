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
}

private final class RenderToken {
  let pointer = ov_ios_token_new()!
  deinit { ov_ios_token_free(pointer) }
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
          let loader = id.hasPrefix("omnivox-icon:personal/") ? resources.personal : resources.loader
          pcm = ov_ios_sound(loader, id, item.gain ?? 1, token.pointer)
        }
        let buffer = pcm.flatMap { pcm -> AVAudioPCMBuffer? in
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
  private let tones: EffectStream, sounds: EffectStream, inserts: EffectStream
  private var speech: AVSpeechUtterance?, spoken: ((Bool) -> Void)?, pause: DispatchWorkItem?
  var interrupted: (() -> Void)?
  private var observers: [NSObjectProtocol] = []

  init(_ resources: WireResources) {
    let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
    tones = EffectStream(resources, format: format)
    sounds = EffectStream(resources, format: format)
    inserts = EffectStream(resources, format: format)
    super.init()
    synth.delegate = self
    synth.usesApplicationAudioSession = false
    for node in [tones.node, sounds.node, inserts.node] {
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

  func play(_ item: WireItem, done: @escaping (Bool) -> Void) {
    switch item.kind {
    case .speech:
      guard let words = item.text, !words.isEmpty else { done(true); return }
      let utterance = AVSpeechUtterance(string: words)
      guard let id = item.voice, let selected = AVSpeechSynthesisVoice(identifier: id) else { done(false); return }
      utterance.voice = selected
      utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate,
          (item.rate ?? 1) * AVSpeechUtteranceDefaultSpeechRate))
      utterance.pitchMultiplier = item.pitch ?? 1
      utterance.volume = item.gain ?? 1
      speech = utterance
      spoken = done
      synth.speak(utterance)
    case .silence:
      let task = DispatchWorkItem(block: { done(true) })
      pause = task
      DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Int(item.ms ?? 0)), execute: task)
    case .sound, .tone:
      do {
        if !engine.isRunning {
          let session = AVAudioSession.sharedInstance()
          try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
          try session.setActive(true)
          try engine.start()
        }
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
