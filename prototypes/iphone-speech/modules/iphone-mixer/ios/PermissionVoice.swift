// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later
import AVFoundation
import ExpoModulesCore

// The foreground speaker and external keyboard never own this synthesizer.
final class PermissionVoice: NSObject, AVSpeechSynthesizerDelegate {
  private let synth = AVSpeechSynthesizer()
  private var active: AVSpeechUtterance?
  private var completion: Promise?

  override init() {
    super.init()
    synth.usesApplicationAudioSession = false
    synth.delegate = self
  }

  func speak(_ text: String, voice: String?, rate: Double, promise: Promise) {
    stop()
    let utterance = AVSpeechUtterance(string: text)
    if let voice { utterance.voice = AVSpeechSynthesisVoice(identifier: voice) }
    utterance.rate = Float(rate) * AVSpeechUtteranceDefaultSpeechRate
    active = utterance
    completion = promise
    synth.speak(utterance)
  }

  func stop() {
    active = nil
    let promise = completion
    completion = nil
    synth.stopSpeaking(at: .immediate)
    promise?.resolve(false)
  }

  private func finish(_ utterance: AVSpeechUtterance, played: Bool) {
    DispatchQueue.main.async { [weak self] in
      guard let self, self.active === utterance else { return }
      self.active = nil
      self.completion?.resolve(played)
      self.completion = nil
    }
  }
  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    finish(utterance, played: true)
  }
  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
    finish(utterance, played: false)
  }
}
