// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

// The trace lives in memory. A callback keeps the ticket from its own reading
// so turning logging on again cannot resurrect text from an earlier session.
final class WireSpeechTrace {
  struct Ticket { fileprivate let epoch: UInt64, id: UInt64 }
  private let lock = NSLock(), limit = 64 * 1024
  private var enabled = false, epoch: UInt64 = 0, serial: UInt64 = 0
  private var rows: [String] = [], bytes = 0

  func setEnabled(_ value: Bool) {
    lock.lock()
    defer { lock.unlock() }
    guard enabled != value else { return }
    enabled = value
    epoch &+= 1
    rows.removeAll()
    bytes = 0
  }

  func begin(_ body: @autoclosure () -> String) -> Ticket? {
    lock.lock()
    defer { lock.unlock() }
    guard enabled else { return nil }
    serial &+= 1
    store(serial, body())
    return Ticket(epoch: epoch, id: serial)
  }

  func append(_ ticket: Ticket?, _ body: @autoclosure () -> String) {
    guard let ticket else { return }
    lock.lock()
    defer { lock.unlock() }
    guard enabled && ticket.epoch == epoch else { return }
    store(ticket.id, body())
  }

  private func store(_ id: UInt64, _ body: String) {
    let prefix = "[\(id)] ", suffix = " … [entry truncated]"
    var line = prefix + body
    if line.utf8.count >= limit {
      let text = body.utf8
      var end = text.index(text.startIndex, offsetBy: limit - prefix.utf8.count - suffix.utf8.count - 1)
      while text[end] & 0xc0 == 0x80 { end = text.index(before: end) }
      line = prefix + String(decoding: text[..<end], as: UTF8.self) + suffix
    }
    let size = line.utf8.count + 1
    while bytes + size > limit || rows.count >= 256 { bytes -= rows.removeFirst().utf8.count + 1 }
    rows.append(line)
    bytes += size
  }

  func snapshot() -> String {
    lock.lock()
    defer { lock.unlock() }
    return rows.joined(separator: "\n")
  }
}
