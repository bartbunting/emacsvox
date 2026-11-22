// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later

import AVFoundation
import ExpoModulesCore

private struct MixerFailure: LocalizedError {
  let message: String
  init(_ message: String) { self.message = message }
  var errorDescription: String? { message }
}

// The graph and the current request belong to the main queue. Each synthesis
// and player callback captures its request so a late callback cannot revive it.
private final class Reading {
  let synthesizer = AVSpeechSynthesizer()
  let promise: Promise
  let started = ProcessInfo.processInfo.systemUptime
  let mixSample: Bool
  var firstBufferMs: Int?
  var pending = 0
  var pendingFrames = 0
  var ended = false
  var deadline = ProcessInfo.processInfo.systemUptime + 8

  init(_ promise: Promise, mixSample: Bool) {
    self.promise = promise
    self.mixSample = mixSample
  }
}

private final class QueuedTone {
  let hz: Double
  let frames: Int
  var cursor = 0
  init(hz: Double, frames: Int) { self.hz = hz; self.frames = frames }
}

public final class IphoneMixerModule: Module {
  private let permissions = PermissionVoice()
  private let engine = AVAudioEngine()
  private let voice = AVAudioPlayerNode()
  private let cue = AVAudioPlayerNode()
  private let tone = AVAudioPlayerNode()
  private var toneGeneration = 0
  private var toneBuffers = 0
  private var pendingTones: [QueuedTone] = []
  private var recording: AVAudioPCMBuffer?
  private var beep: AVAudioPCMBuffer?
  private var voiceFormat: AVAudioFormat?
  private var current: Reading?
  private var configObserver: NSObjectProtocol?
  private var interruptionObserver: NSObjectProtocol?

  public func definition() -> ModuleDefinition {
    Name("IphoneMixer")

    AsyncFunction("permission") { (text: String, voice: String?, rate: Double, promise: Promise) in
      self.permissions.speak(text, voice: voice, rate: rate, promise: promise)
    }.runOnQueue(.main)

    AsyncFunction("stopPermission") { self.permissions.stop() }.runOnQueue(.main)

    AsyncFunction("prepare") { (uri: String) in
      try self.prepare(uri)
    }.runOnQueue(.main)

    AsyncFunction("speak") { (text: String, identifier: String?, rate: Double, mixSample: Bool, promise: Promise) in
      self.read(text, identifier: identifier, rate: rate, mixSample: mixSample, promise: promise)
    }.runOnQueue(.main)

    AsyncFunction("cue") {
      try self.startAudio()
      if let recording = self.recording { self.play(recording, on: self.cue) }
    }.runOnQueue(.main)

    AsyncFunction("queueTone") { (hz: Double, ms: Int) in
      guard hz.isFinite, hz > 0, hz <= 24000, (1...60000).contains(ms),
            self.pendingTones.count < 1024, let format = self.beep?.format else { throw MixerFailure("Invalid tone.") }
      try self.startAudio()
      self.pendingTones.append(QueuedTone(hz: hz, frames: Int(format.sampleRate * Double(ms) / 1000)))
      self.fillTones()
    }.runOnQueue(.main)

    AsyncFunction("stopEffects") {
      self.cue.stop()
      self.stopTones()
    }.runOnQueue(.main)

    AsyncFunction("stop") { (all: Bool) in
      self.finish("stopped")
      if all { self.cue.stop(); self.stopTones() }
    }.runOnQueue(.main)

    OnDestroy {
      DispatchQueue.main.async {
        self.finish("stopped")
        self.permissions.stop()
        self.stopTones()
        self.engine.stop()
        if let observer = self.configObserver { NotificationCenter.default.removeObserver(observer) }
        if let observer = self.interruptionObserver { NotificationCenter.default.removeObserver(observer) }
      }
    }
  }

  private func prepare(_ uri: String) throws {
    if recording != nil { return }
    guard let url = URL(string: uri), url.isFileURL else { throw MixerFailure("Missing local Accent sound.") }
    let file = try AVAudioFile(forReading: url)
    guard file.length > 0, file.length <= 100000,
          let sound = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
          let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1),
          let signal = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4800),
          let data = signal.floatChannelData?[0] else { throw MixerFailure("Cannot prepare the test sounds.") }
    try file.read(into: sound)
    signal.frameLength = signal.frameCapacity
    for frame in 0..<Int(signal.frameLength) {
      let edge = min(1.0, Double(min(frame, Int(signal.frameLength) - 1 - frame)) / 220)
      data[frame] = Float(0.15 * edge * sin(2 * .pi * 660 * Double(frame) / format.sampleRate))
    }
    for node in [voice, cue, tone] { engine.attach(node) }
    engine.connect(cue, to: engine.mainMixerNode, format: sound.format)
    engine.connect(tone, to: engine.mainMixerNode, format: format)
    recording = sound
    beep = signal
    configObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
      self?.resetOutput()
    }
    interruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
      if let kind = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
         kind == AVAudioSession.InterruptionType.began.rawValue { self?.resetOutput() }
    }
  }

  private func resetOutput() {
    finish("audio route changed")
    cue.stop()
    stopTones()
  }

  private func startAudio() throws {
    guard recording != nil else { throw MixerFailure("Mixer is still loading.") }
    if engine.isRunning { return }
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
    try session.setActive(true)
    try engine.start()
  }

  private func play(_ buffer: AVAudioPCMBuffer, on player: AVAudioPlayerNode) {
    player.stop()
    player.scheduleBuffer(buffer)
    player.play()
  }

  private func stopTones() {
    toneGeneration &+= 1
    pendingTones.removeAll()
    toneBuffers = 0
    tone.stop()
  }

  private func fillTones() {
    guard let format = beep?.format else { return }
    // Keep at most two small PCM buffers scheduled so Stop remains responsive.
    while toneBuffers < 2, let note = pendingTones.first {
      let count = min(2048, note.frames - note.cursor)
      guard let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
            let samples = pcm.floatChannelData?[0] else { stopTones(); return }
      pcm.frameLength = AVAudioFrameCount(count)
      for index in 0..<count {
        let position = note.cursor + index
        let edge = min(1.0, Double(min(position, note.frames - position - 1)) / (format.sampleRate * 0.004))
        samples[index] = Float(0.15 * edge * sin(2 * .pi * note.hz * Double(position) / format.sampleRate))
      }
      note.cursor += count
      if note.cursor == note.frames { pendingTones.removeFirst() }
      toneBuffers += 1
      let owner = toneGeneration
      tone.scheduleBuffer(pcm, completionCallbackType: .dataPlayedBack) { [weak self] _ in
        DispatchQueue.main.async {
          guard let self, self.toneGeneration == owner else { return }
          self.toneBuffers -= 1
          self.fillTones()
        }
      }
      if !tone.isPlaying { tone.play() }
    }
  }

  private func read(_ text: String, identifier: String?, rate: Double, mixSample: Bool, promise: Promise) {
    finish("stopped")
    let reading = Reading(promise, mixSample: mixSample)
    current = reading
    let utterance = AVSpeechUtterance(string: text)
    if let identifier {
      guard let selected = AVSpeechSynthesisVoice(identifier: identifier) else {
        finish("selected voice unavailable")
        return
      }
      utterance.voice = selected
    }
    utterance.rate = Float(rate) * AVSpeechUtteranceDefaultSpeechRate
    reading.synthesizer.write(utterance) { [weak self, weak reading] buffer in
      // Own the PCM before returning it to the synthesizer.
      let samples = Result { try Self.copySamples(buffer) }
      DispatchQueue.main.async {
        guard let self, let reading, self.current === reading else { return }
        do {
          if let pcm = try samples.get() { try self.schedule(pcm, reading) }
          else { reading.ended = true; self.completeIfPlayed(reading) }
        } catch { self.finish("audio buffer failed") }
      }
    }
    watchProgress(reading)
  }

  private func watchProgress(_ reading: Reading) {
    let remaining = reading.deadline - ProcessInfo.processInfo.systemUptime
    guard remaining > 0 else {
      finish(reading.firstBufferMs == nil ? "voice returned no samples" : "playback timed out")
      return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak self, weak reading] in
      guard let self, let reading, self.current === reading else { return }
      self.watchProgress(reading)
    }
  }

  private static func copySamples(_ buffer: AVAudioBuffer) throws -> AVAudioPCMBuffer? {
    guard let pcm = buffer as? AVAudioPCMBuffer else { throw MixerFailure("Unexpected speech buffer.") }
    guard pcm.frameLength > 0 else { return nil }
    guard (1...2).contains(pcm.format.channelCount), (8000...192000).contains(pcm.format.sampleRate),
          let format = AVAudioFormat(standardFormatWithSampleRate: pcm.format.sampleRate, channels: pcm.format.channelCount),
          let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: pcm.frameLength)
    else { throw MixerFailure("Unsupported PCM format.") }
    if pcm.format == format, let input = pcm.floatChannelData, let output = copy.floatChannelData {
      copy.frameLength = pcm.frameLength
      for channel in 0..<Int(format.channelCount) {
        output[channel].update(from: input[channel], count: Int(pcm.frameLength))
      }
    } else {
      guard let converter = AVAudioConverter(from: pcm.format, to: format) else { throw MixerFailure("Unsupported PCM conversion.") }
      try converter.convert(to: copy, from: pcm)
    }
    return copy
  }

  private func schedule(_ pcm: AVAudioPCMBuffer, _ reading: Reading) throws {
    if reading.firstBufferMs == nil {
      reading.firstBufferMs = Int((ProcessInfo.processInfo.systemUptime - reading.started) * 1000)
      if voiceFormat != pcm.format {
        engine.connect(voice, to: engine.mainMixerNode, format: pcm.format)
        voiceFormat = pcm.format
      }
    }
    guard voiceFormat == pcm.format, reading.pendingFrames + Int(pcm.frameLength) <= Int(pcm.format.sampleRate * 120) else {
      throw MixerFailure("Voice exceeded the experiment's PCM limit.")
    }
    try startAudio()
    reading.pending += 1
    let frames = Int(pcm.frameLength)
    reading.pendingFrames += frames
    reading.deadline = ProcessInfo.processInfo.systemUptime + Double(reading.pendingFrames) / pcm.format.sampleRate + 8
    voice.scheduleBuffer(pcm, completionCallbackType: .dataPlayedBack) { [weak self, weak reading] _ in
      DispatchQueue.main.async {
        guard let self, let reading, self.current === reading else { return }
        reading.pending -= 1
        reading.pendingFrames -= frames
        self.completeIfPlayed(reading)
      }
    }
    if !voice.isPlaying {
      voice.play()
      if reading.mixSample, let sound = recording, let signal = beep {
        play(sound, on: cue)
        play(signal, on: tone)
      }
    }
  }

  private func completeIfPlayed(_ reading: Reading) {
    if reading.ended && reading.pending == 0 {
      finish(reading.firstBufferMs == nil ? "voice returned no samples" : "done")
    }
  }

  private func finish(_ state: String) {
    guard let reading = current else { return }
    current = nil
    voice.stop()
    if state != "done" { reading.synthesizer.stopSpeaking(at: .immediate) }
    if state != "stopped" && state != "done" { cue.stop(); stopTones() }
    reading.promise.resolve(["state": state, "firstBufferMs": reading.firstBufferMs ?? -1] as [String: Any])
  }
}
