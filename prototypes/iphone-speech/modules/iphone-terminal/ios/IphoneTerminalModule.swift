// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later
import EmacsTerminalSSH
import ExpoModulesCore
import SwiftTerm
import UIKit

public final class IphoneTerminalModule: Module {
  public func definition() -> ModuleDefinition {
    Name("IphoneTerminal")
    AsyncFunction("copyPublicKey") { UIPasteboard.general.string = try PhoneIdentity.publicKey() }.runOnQueue(.main)
    Function("loadProfile") { UserDefaults.standard.dictionary(forKey: "emacsvox.ssh.profile") as? [String:String] ?? [:] }
    Function("saveProfile") { (profile: [String:String]) in UserDefaults.standard.set(profile, forKey: "emacsvox.ssh.profile") }
    View(PhoneTerminalView.self) {
      Events("onSessionStatus")
      Prop("connection") { (view: PhoneTerminalView, config: [String: String]) in view.configure(config) }
      AsyncFunction("focusKeyboard") { (view: PhoneTerminalView) in
        view.terminal.becomeFirstResponder()
        UIAccessibility.post(notification: .layoutChanged, argument: view.terminal)
      }
    }
  }
}

final class PhoneTerminalView: ExpoView, TerminalViewDelegate {
  let terminal = TerminalView(frame: .zero)
  let onSessionStatus = EventDispatcher()
  private var configuration: [String: String] = [:]
  private var connection: Task<Void, Never>?
  private var session: TerminalSession?
  private var writes: Task<Void, Never>?
  private var pendingBytes = 0
  private var generation = UUID()
  private var rows = 24
  private var columns = 80

  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    terminal.optionAsMetaKey = true
    terminal.accessibilityLabel = "Emacs terminal"
    terminal.terminalDelegate = self
    addSubview(terminal)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    terminal.frame = bounds
  }

  private func close() {
    generation = UUID()
    connection?.cancel()
    connection = nil
    writes?.cancel()
    writes = nil
    pendingBytes = 0
    if let session { Task { try? await session.disconnect() } }
    session = nil
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window == nil { close() }
    else if connection == nil && session == nil { start() }
  }

  func configure(_ config: [String: String]) {
    guard config != configuration else { return }
    close()
    configuration = config
    if window != nil { start() }
  }

  private func start() {
    let config = configuration
    guard let host = config["host"], let port = Int(config["port"] ?? ""),
          let user = config["username"], let pin = config["pin"],
          let server = config["server"], let client = config["client"], let frame = config["frame"] else { return }
    let owner = generation
    connection = Task { @MainActor [weak self] in
      guard let self else { return }
      do {
        let size = try TerminalSize(columns: columns, rows: rows)
        let live = try await PhoneIdentity.connect(host: host, port: port, username: user, pin: pin,
          server: server, client: client, frame: frame, size: size) { [weak self] bytes in
          DispatchQueue.main.async {
            guard let self, self.generation == owner else { return }
            self.terminal.feed(byteArray: bytes[...])
          }
        }
        guard generation == owner else { try? await live.disconnect(); return }
        session = live
        try await live.resize(TerminalSize(columns: columns, rows: rows))
        onSessionStatus(["state":"connected"])
        _ = try await live.waitForExit()
        if generation == owner { close(); onSessionStatus(["state":"closed"]) }
      } catch {
        if generation == owner {
          let reason: String
          switch error {
          case TerminalError.hostKeyMismatch: reason = "The SSH host key does not match."
          case TerminalError.keyRejected: reason = "WSL rejected the iPhone public key."
          default: reason = "Could not open the SSH terminal."
          }
          close()
          onSessionStatus(["state":"failed", "detail":reason])
        }
      }
    }
  }

  func send(source: TerminalView, data: ArraySlice<UInt8>) {
    guard let session else { return }
    let bytes = Array(data), owner = generation, previous = writes
    pendingBytes += bytes.count
    guard pendingBytes <= 65536 else { close(); onSessionStatus(["state":"failed", "detail":"Terminal input queue full."]); return }
    writes = Task { @MainActor [weak self] in
      await previous?.value
      guard let self, generation == owner else { return }
      do { try await session.send(bytes) }
      catch { if generation == owner { close(); onSessionStatus(["state":"closed"]) }; return }
      if generation == owner { pendingBytes -= bytes.count }
    }
  }
  func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
    guard newCols > 0, newRows > 0 else { return }
    columns = newCols
    rows = newRows
    if let session { Task { try? await session.resize(TerminalSize(columns: newCols, rows: newRows)) } }
  }
  func setTerminalTitle(source: TerminalView, title: String) {}
  func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
  func scrolled(source: TerminalView, position: Double) {}
  func requestOpenLink(source: TerminalView, link: String, params: [String:String]) {}
  func bell(source: TerminalView) {}
  func clipboardCopy(source: TerminalView, content: Data) {}
  func clipboardRead(source: TerminalView) -> Data? { nil }
  func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
  func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}
