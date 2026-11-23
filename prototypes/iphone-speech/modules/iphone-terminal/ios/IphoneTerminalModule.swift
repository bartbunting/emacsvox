// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later
import EmacsTerminalSSH
import ExpoModulesCore
import SwiftTerm
import UIKit

public final class IphoneTerminalModule: Module {
  private var holdsIdleTimer = false

  public func definition() -> ModuleDefinition {
    Name("IphoneTerminal")
    AsyncFunction("copyPublicKey") { UIPasteboard.general.string = try PhoneIdentity.publicKey() }.runOnQueue(.main)
    Function("loadProfile") { UserDefaults.standard.dictionary(forKey: "emacsvox.ssh.profile") as? [String:String] ?? [:] }
    Function("saveProfile") { (profile: [String:String]) in UserDefaults.standard.set(profile, forKey: "emacsvox.ssh.profile") }
    AsyncFunction("keepAwake") { (enabled: Bool) in
      if enabled && !UIApplication.shared.isIdleTimerDisabled {
        UIApplication.shared.isIdleTimerDisabled = true
        self.holdsIdleTimer = true
      } else if !enabled && self.holdsIdleTimer {
        UIApplication.shared.isIdleTimerDisabled = false
        self.holdsIdleTimer = false
      }
    }.runOnQueue(.main)
    OnDestroy {
      DispatchQueue.main.async {
        if self.holdsIdleTimer { UIApplication.shared.isIdleTimerDisabled = false }
      }
    }
    View(PhoneTerminalView.self) {
      Events("onSessionStatus")
      Prop("connection") { (view: PhoneTerminalView, config: [String: String]) in view.configure(config) }
      Prop("keyboardEnabled") { (view: PhoneTerminalView, enabled: Bool) in
        view.terminal.isUserInteractionEnabled = enabled
        if !enabled && view.terminal.isFirstResponder { view.terminal.resignFirstResponder() }
      }
      AsyncFunction("focusKeyboard") { (view: PhoneTerminalView) in
        guard view.terminal.isUserInteractionEnabled else { return }
        view.terminal.becomeFirstResponder()
        UIAccessibility.post(notification: .layoutChanged, argument: view.terminal)
      }
      AsyncFunction("sendKeys") { (view: PhoneTerminalView, frame: String, text: String) in
        view.sendKeys(text, to: frame)
      }
      AsyncFunction("visibleRows") { (view: PhoneTerminalView, frame: String) -> [String] in
        view.visibleRows(for: frame)
      }
    }
  }
}

private final class EmacsTerminalView: TerminalView {
  override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    guard optionAsMetaKey, markedTextRange == nil, getTerminal().keyboardEnhancementFlags.isEmpty else {
      super.pressesBegan(presses, with: event)
      return
    }
    var remaining = presses
    for press in presses {
      guard let key = press.key, key.modifierFlags.contains([.alternate, .shift]),
            key.modifierFlags.intersection([.control, .command]).isEmpty else { continue }
      let symbol: String
      switch key.charactersIgnoringModifiers {
      case ",": symbol = "<"
      case ".": symbol = ">"
      default: continue
      }
      send(txt: "\u{1b}" + symbol)
      remaining.remove(press)
    }
    if !remaining.isEmpty { super.pressesBegan(remaining, with: event) }
  }
}

final class PhoneTerminalView: ExpoView, TerminalViewDelegate {
  let terminal: TerminalView = EmacsTerminalView(frame: .zero)
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
    terminal.nativeBackgroundColor = .black
    terminal.nativeForegroundColor = .white
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
        if generation == owner { close(); onSessionStatus(["state":"closed", "frame":frame]) }
      } catch {
        if generation == owner {
          let reason: String
          switch error {
          case TerminalError.hostKeyMismatch: reason = "The SSH host key does not match."
          case TerminalError.keyRejected: reason = "WSL rejected the iPhone public key."
          default: reason = "Could not open the SSH terminal."
          }
          close()
          onSessionStatus(["state":"failed", "frame":frame, "detail":reason])
        }
      }
    }
  }

  func sendKeys(_ text: String, to frame: String) {
    guard terminal.isUserInteractionEnabled, configuration["frame"] == frame,
          !text.isEmpty, text.utf8.count <= 1024 else { return }
    send(source: terminal, data: Array(text.utf8)[...])
  }

  func visibleRows(for frame: String) -> [String] {
    guard configuration["frame"] == frame, session != nil else { return [] }
    let screen = terminal.getTerminal()
    return (0..<screen.rows).compactMap { row in
      guard let line = screen.getLine(row: row) else { return nil }
      let text = line.translateToString(trimRight: true, skipNullCellsFollowingWide: true,
                                        characterProvider: { screen.getCharacter(for: $0) })
                     .replacingOccurrences(of: "\0", with: " ")
      return text.trimmingCharacters(in: .whitespaces).isEmpty ? nil : text
    }
  }

  func send(source: TerminalView, data: ArraySlice<UInt8>) {
    guard let session, let frame = configuration["frame"] else { return }
    let bytes = Array(data), owner = generation, previous = writes
    pendingBytes += bytes.count
    guard pendingBytes <= 65536 else { close(); onSessionStatus(["state":"failed", "frame":frame, "detail":"Terminal input queue full."]); return }
    writes = Task { @MainActor [weak self] in
      await previous?.value
      guard let self, generation == owner else { return }
      do { try await session.send(bytes) }
      catch { if generation == owner { close(); onSessionStatus(["state":"closed", "frame":frame]) }; return }
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
