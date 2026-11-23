// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later
import AVFoundation
import AudioToolbox
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
  return wireBufferSlice(pcm, format: format, frames: 0..<ov_ios_frames(pcm))
}

func wireBufferSlice(_ pcm: OpaquePointer, format: AVAudioFormat, frames: Range<Int>) -> AVAudioPCMBuffer? {
  let count = frames.count
  guard count > 0, let source = ov_ios_samples(pcm),
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
        let planes = buffer.floatChannelData else { return nil }
  buffer.frameLength = AVAudioFrameCount(count)
  for i in 0..<count {
    planes[0][i] = source[2 * (frames.lowerBound + i)]
    planes[1][i] = source[2 * (frames.lowerBound + i) + 1]
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
          pcm = item.tonePCM(token.pointer)
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
  private let resources: WireResources
  private let trace: WireSpeechTrace, lane: String
  private let preparation = DispatchQueue(label: "org.emacsvox.iphone.resource-preparation", qos: .userInitiated)
  private let bufferSynth = AVSpeechSynthesizer()
  private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
  private lazy var scheduleGain = engine.mainMixerNode.auAudioUnit.scheduleParameterBlock
  private var fading: [ObjectIdentifier: AVAudioPlayerNode] = [:]
  private var available: [AVAudioPlayerNode] = []
  private var playing: [ObjectIdentifier: (WirePlayback<AVAudioPCMBuffer>, WireMixer, AVAudioPlayerNode)] = [:]
  private let tones: EffectStream, sounds: EffectStream, inserts: EffectStream
  private var speech: AVSpeechUtterance?, spoken: ((Bool) -> Void)?, pause: DispatchWorkItem?
  var interrupted: (() -> Void)?
  var resolvedMarks: ((WireTimingReport) -> Void)?
  private var observers: [NSObjectProtocol] = []

  init(_ resources: WireResources, trace: WireSpeechTrace, lane: String) {
    self.resources = resources
    self.trace = trace
    self.lane = lane
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
      _ = scheduleGain
      try engine.start()
    }
  }

  func playMixed(_ items: ArraySlice<WireItem>, reached: @escaping (String) -> Void, holdTail: @escaping () -> () -> Void, done: @escaping (Int, Bool) -> Void) {
    startRun(items, presentation: nil, reached: reached, holdTail: holdTail, done: done)
  }

  func playTimeline(_ plan: WirePresentation, holdTail: @escaping () -> () -> Void, done: @escaping (Bool) -> Void) {
    preparation.async { [resources] in
      let items = plan.prepare(bundle: resources.loader, personal: resources.personal)
      DispatchQueue.main.async { [weak self] in
        guard !plan.cancelled else { return }
        guard let self, let items else { done(false); return }
        if items.isEmpty { done(true); return }
        self.startRun(items[...], presentation: plan, reached: nil, holdTail: holdTail) { count, ok in
          done(ok && count == items.count)
        }
      }
    }
  }

  private func startRun(_ items: ArraySlice<WireItem>, presentation: WirePresentation?, reached: ((String) -> Void)?,
                        holdTail: @escaping () -> () -> Void, done: @escaping (Int, Bool) -> Void) {
    do { try startAudio() } catch { done(0, presentation == nil); return }
    // A previous dispatch may still own this lane's overlay tail.
    let node: AVAudioPlayerNode
    if let idle = available.popLast() { node = idle }
    else {
      node = AVAudioPlayerNode()
      engine.attach(node)
      engine.connect(node, to: engine.mainMixerNode, format: format)
    }
    let key = ObjectIdentifier(node)
    node.volume = 1
    let mixer = WireMixer(format: format, synth: bufferSynth, trace: trace, lane: lane,
                          resolvedMarks: resolvedMarks, presentation: presentation, reached: reached)
    let playback = WirePlayback<AVAudioPCMBuffer>(items, speech: mixer.speech, flush: mixer.flush,
      enqueue: { buffer, played in
        node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in
          DispatchQueue.main.async { mixer.played(buffer); played() }
        }
        if !node.isPlaying { node.play() }
      }, holdTail: holdTail, done: done, release: { [weak self] in
        presentation?.stopPlayer = nil
        self?.playing.removeValue(forKey: key)
        node.stop()
        self?.available.append(node)
      })
    presentation?.stopPlayer = { [weak self] replacing in
      guard let self, let (run, mixer, player) = self.playing.removeValue(forKey: key) else { return }
      run.stop()
      mixer.cancel()
      self.retire(player, replacing: replacing)
    }
    playing[key] = (playback, mixer, node)
    playback.advance()
  }

  private func retire(_ player: AVAudioPlayerNode, replacing: Bool) {
    let mixer = engine.mainMixerNode
    guard replacing, player.isPlaying, engine.isRunning,
          let route = engine.outputConnectionPoints(for: player, outputBus: 0).first(where: { $0.node === mixer }),
          let gain = mixer.auAudioUnit.parameterTree?.parameter(withID: kMultiChannelMixerParam_Volume,
            scope: kAudioUnitScope_Input, element: UInt32(route.bus)), gain.flags.contains(.flag_CanRamp)
    else {
      player.stop()
      available.append(player)
      return
    }
    let frames = AUAudioFrameCount((mixer.outputFormat(forBus: 0).sampleRate * 0.003).rounded())
    scheduleGain(AUEventSampleTimeImmediate, frames, gain.address, 0)
    let key = ObjectIdentifier(player)
    fading[key] = player
    // Keep this bus private until its hardware render quantum consumes the ramp.
    let grace = AVAudioSession.sharedInstance().ioBufferDuration + 0.003
    DispatchQueue.main.asyncAfter(deadline: .now() + grace) { [weak self] in
      guard let self, self.fading.removeValue(forKey: key) != nil else { return }
      player.stop()
      gain.value = 1
      self.available.append(player)
    }
  }

  func play(_ item: WireItem, done: @escaping (Bool) -> Void) {
    switch item.kind {
    case .speech:
      guard !(item.text ?? "").isEmpty else { done(true); return }
      guard let utterance = wireUtterance(item) else { done(false); return }
      _ = trace.begin("\(lane) direct speech \(utterance.speechString.debugDescription)")
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
    for node in fading.values { node.stop() }
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
