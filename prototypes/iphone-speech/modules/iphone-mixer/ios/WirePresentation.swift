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
  private let reply: (String) -> Void
  private(set) var cancelled = false
  var stopPlayer: ((Bool) -> Void)?

  init(_ pointer: OpaquePointer, key: String?, reply: @escaping (String) -> Void) {
    self.pointer = pointer
    self.key = key
    self.reply = reply
  }
  deinit { ov_ios_presentation_free(pointer); ov_ios_token_free(token) }

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
    guard frames > 0, let events = decode(ov_ios_playback_events(pointer), as: [WirePlayedEvent].self) else { return nil }
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
