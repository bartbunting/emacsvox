// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import OmnivoxMobile

struct WireAnchor: Decodable {
  let offset: Int
  var after: Bool?
}

struct WirePlayedEvent: Decodable {
  let frame: Int, line: String
}

struct WireAudioRegion {
  let frames: Range<Int>, events: [String]
}

// The output driver owns the render queue. Stop may cancel its token on main
// while Rust loads a resource or converts speech. Only main delivers receipts.
final class WirePresentation {
  let pointer: OpaquePointer, token = ov_ios_token_new()!
  let key: String?
  let isPreview: Bool
  private var preview: OpaquePointer?, accepted = false, started = false  // playback queue
  private var needsFirstFrame = true  // render queue
  private let reply: (String) -> Void
  private(set) var cancelled = false
  var stopPlayer: ((Bool) -> Void)?

  init(_ pointer: OpaquePointer, key: String?, preview: OpaquePointer? = nil, reply: @escaping (String) -> Void) {
    self.pointer = pointer
    self.preview = preview
    isPreview = preview != nil
    self.key = key
    self.reply = reply
  }
  deinit {
    if let preview { ov_ios_preview_free(preview) }
    ov_ios_presentation_free(pointer)
    ov_ios_token_free(token)
  }

  func acceptedAudio() {
    guard !cancelled, !accepted, let preview else { return }
    accepted = true
    ov_ios_preview_accepted(preview)
  }

  func startedAudio() {
    guard !cancelled, !started, let preview else { return }
    started = true
    ov_ios_preview_started(preview)
  }

  func finishPreview(_ status: OvPreviewStatus) {
    guard let preview else { return }
    self.preview = nil
    if let line = ov_ios_preview_finish(preview, UInt8(status.rawValue)) {
      defer { ov_ios_string_free(line) }
      reply(String(cString: line))
    }
  }

  func cancel(replacing: Bool = false) {
    guard !cancelled else { return }
    cancelled = true
    ov_ios_cancel(token)
    stopPlayer?(replacing)
    stopPlayer = nil
  }

  func reached(_ lines: [String]) {
    if !cancelled { for line in lines { reply(line) } }
  }

  private func decode<T: Decodable>(_ raw: UnsafeMutablePointer<CChar>?, as: T.Type) -> T? {
    guard let raw else { return nil }
    defer { ov_ios_string_free(raw) }
    return try? JSONDecoder().decode(T.self, from: Data(bytes: raw, count: strlen(raw)))
  }

  func prepare(bundle: OpaquePointer, personal: OpaquePointer?) -> [WireItem]? {
    decode(ov_ios_prepare_presentation(pointer, bundle, personal, token), as: [WireItem].self)
  }

  // End a hardware buffer exactly where a new event becomes audible.
  // A zero-offset event is acknowledged after the first played frame.
  func regions(frames: Int) -> [WireAudioRegion]? {
    guard frames > 0 else { return nil }
    if isPreview {
      if needsFirstFrame {
        needsFirstFrame = false
        if frames > 1 {
          return [WireAudioRegion(frames: 0..<1, events: []), WireAudioRegion(frames: 1..<frames, events: [])]
        }
      }
      return [WireAudioRegion(frames: 0..<frames, events: [])]
    }
    guard let events = decode(ov_ios_playback_events(pointer), as: [WirePlayedEvent].self) else { return nil }
    var groups: [(end: Int, lines: [String])] = []
    for event in events {
      guard (0...frames).contains(event.frame) else { return nil }
      let end = max(1, event.frame)
      if let last = groups.indices.last, groups[last].end == end {
        groups[last].lines.append(event.line)
      } else {
        guard end > (groups.last?.end ?? 0) else { return nil }
        groups.append((end, [event.line]))
      }
    }
    if groups.last?.end != frames { groups.append((frames, [])) }
    var start = 0
    return groups.map { group in
      defer { start = group.end }
      return WireAudioRegion(frames: start..<group.end, events: group.lines)
    }
  }
}
