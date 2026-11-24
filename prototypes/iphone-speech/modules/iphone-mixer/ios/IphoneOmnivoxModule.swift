// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later
import AVFoundation
import ExpoModulesCore
import OmnivoxMobile

private enum WireFailure: Error { case resources, voices, action }
public final class IphoneOmnivoxModule: Module {
  private var lanes: [String: WireLane] = [:]
  private var connection = 0
  private var catalogue = ""
  private let inventory = WireVoiceInventory()
  private var inventoryObserver: NSObjectProtocol?
  private var markerStatus: String?
  private weak var mainAudio: WireAudio?
  private let importer = CueImport()
  private let trace = WireSpeechTrace()
  private var speechBoost: UInt8 = 0

  public func definition() -> ModuleDefinition {
    Name("IphoneOmnivox")
    Events("wireReply", "keyTiming")
    Function("timingClock") { wireUptimeMilliseconds() }
    AsyncFunction("armKeyTiming") { (id: Int, serial: Int) in
      guard self.connection == id, let audio = self.mainAudio else { throw WireFailure.action }
      audio.keyTimingSample = (1...255).contains(serial) ? serial : nil
    }.runOnQueue(.main)
    AsyncFunction("setSpeechLoudness") { (db: Int) in
      self.speechBoost = UInt8(min(6, max(0, db)))
    }.runOnQueue(.main)
    View(PhoneSpeechLoudnessView.self) {
      ViewName("PhoneSpeechLoudnessView")
      Events("onLevelChange")
      Prop("level") { (view: PhoneSpeechLoudnessView, db: Int) in view.setLevel(db) }
    }
    Function("setSpeechLogging") { (enabled: Bool) in self.trace.setEnabled(enabled) }
    Function("speechTrace") { self.trace.snapshot() }
    AsyncFunction("importCue") { (promise: Promise) in
      guard let controller = self.appContext?.utilities?.currentViewController() else { throw CueImportError.busy }
      try self.importer.pick(from: controller) { result in
        switch result {
        case .success(let imported): promise.resolve(imported)
        case .failure: promise.reject("ERR_CUE_IMPORT", "Choose a WAV or OGG file up to 16 MiB and 30 seconds.")
        }
      }
    }.runOnQueue(.main)
    AsyncFunction("open") { (id: Int) in
      self.close()
      self.connection = id
      let bundles = [Bundle.main, Bundle(for: IphoneOmnivoxModule.self)]
      guard let root = bundles.compactMap({ $0.url(forResource: "OmnivoxSounds", withExtension: "bundle") }).first,
            let resources = WireResources(at: root) else { throw WireFailure.resources }
      for tag in ["M", "N"] {
        let audio = WireAudio(resources, trace: self.trace, lane: tag)
        audio.speechLoudness = { [weak self] in self?.speechBoost ?? 0 }
        if tag == "M" {
          self.mainAudio = audio
          audio.keyTimingStarted = { [weak self] serial, event, time in
            guard let self, self.connection == id else { return }
            self.sendEvent("keyTiming", ["connection": id, "serial": serial, "event": event, "time": time] as [String: Any])
          }
          audio.resolvedMarks = { [weak self] report in
            if report.exact + report.word + report.span > 0 { self?.markerStatus = report.description }
          }
        }
        let lane = WireLane(audio) { [weak self] line in
          guard let self, self.connection == id else { return }
          self.sendEvent("wireReply", ["connection": id, "record": tag + " " + line] as [String: Any])
        }
        audio.beginSynthesis = { [weak lane] in lane.flatMap { WireSynthesisAttempt($0.worker) } }
        audio.interrupted = { [weak lane] in lane?.stop() }
        self.lanes[tag] = lane
      }
      if #available(iOS 17.0, *) {
        self.inventoryObserver = NotificationCenter.default.addObserver(
          forName: AVSpeechSynthesizer.availableVoicesDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
          guard let self, self.connection == id else { return }
          self.inventory.invalidate()
        }
      }
      try self.inventory.refresh(for: "") { try self.refreshVoices() }
    }.runOnQueue(.main)
    AsyncFunction("record") { (id: Int, tag: String, line: String, muted: Bool) in
      guard self.connection == id, let lane = self.lanes[tag] else { return }
      try self.inventory.refresh(for: line) { try self.refreshVoices() }
      try lane.feed(line, muted: muted)
    }.runOnQueue(.main)
    AsyncFunction("permission") { (id: Int, text: String, promise: Promise) in
      guard self.connection == id, let lane = self.lanes["N"] else { promise.resolve(false); return }
      try lane.permission(text) { played in promise.resolve(played) }
    }.runOnQueue(.main)
    AsyncFunction("diagnostic") { (id: Int, sound: String, promise: Promise) in
      guard self.connection == id, let lane = self.lanes["M"] else { promise.resolve(false); return }
      let done: (Bool) -> Void = { ok in promise.resolve(ok) }
      switch sound {
      case "voice": try lane.permission("This is the iPhone voice test.", done: done)
      case "last-timing": promise.resolve(self.markerStatus ?? "No reading with internal cue positions yet.")
      case "markers":
        let bundles = [Bundle.main, Bundle(for: IphoneOmnivoxModule.self)]
        guard let file = bundles.compactMap({ $0.url(forResource: "CapitalTiming", withExtension: "json") }).first,
              let items = try lane.timingSample(Data(contentsOf: file)), items.count == 1 else { done(false); return }
        self.markerStatus = nil
        lane.schedule.permission(items[0]) { ok in
          promise.resolve(ok ? (self.markerStatus ?? "The voice played without timing marks.") : "Timing test stopped.")
        }
      case "short", "long":
        lane.schedule.diagnosticEffect(WireItem(kind: .tone, placement: .independent, gain: 1, hz: 660, ms: sound == "short" ? 480 : 3000), done: done)
      case "accent", "chime":
        let cue = sound == "accent" ? "packs/accent/open-object.ogg" : "visual-line.wav"
        lane.schedule.diagnosticEffect(WireItem(kind: .sound, gain: 1, path: "omnivox-icon:" + cue), done: done)
      default: promise.resolve(false)
      }
    }.runOnQueue(.main)
    AsyncFunction("stopPermission") { (id: Int) in
      if self.connection == id { self.lanes["N"]?.schedule.stop(all: false) }
    }.runOnQueue(.main)
    AsyncFunction("stop") { (id: Int) in
      if self.connection == id { for lane in self.lanes.values { lane.stop() } }
    }.runOnQueue(.main)
    AsyncFunction("close") { (id: Int) in if self.connection == id { self.close() } }.runOnQueue(.main)
    OnDestroy { DispatchQueue.main.async { self.close() } }
  }

  private func close() {
    connection = 0
    if let inventoryObserver { NotificationCenter.default.removeObserver(inventoryObserver) }
    inventoryObserver = nil
    inventory.invalidate()
    for lane in lanes.values { lane.stop() }
    lanes.removeAll()
    catalogue = ""
    markerStatus = nil
  }

  private func refreshVoices() throws {
    let voices = AVSpeechSynthesisVoice.speechVoices()
    let rows: [[String: String]] = voices.map { voice in
      var row = ["id": voice.identifier, "name": voice.name, "language": voice.language,
                 "quality": voice.quality == .premium ? "premium" : voice.quality == .enhanced ? "enhanced" : "compact"]
      if voice.gender == .male { row["gender"] = "male" }
      if voice.gender == .female { row["gender"] = "female" }
      return row
    }
    let data = try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys])
    guard let json = String(data: data, encoding: .utf8) else { throw WireFailure.voices }
    let english = voices.filter { $0.language.lowercased().hasPrefix("en") }
    let preferred = ["Reed", "Eddy", "Rocko", "Grandpa", "Daniel", "Aaron", "Lee"].compactMap { name -> AVSpeechSynthesisVoice? in
      let matches = english.filter { $0.name.components(separatedBy: " (")[0].caseInsensitiveCompare(name) == .orderedSame }
      return matches.first { $0.language.replacingOccurrences(of: "_", with: "-").lowercased() == "en-us" } ?? matches.first
    }.first ?? AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
    let key = (preferred?.identifier ?? "") + "\n" + json
    guard key != catalogue else { return }
    for lane in lanes.values {
      guard lane.setVoices(json, preferred: preferred?.identifier ?? "") else { throw WireFailure.voices }
    }
    catalogue = key
  }
}
