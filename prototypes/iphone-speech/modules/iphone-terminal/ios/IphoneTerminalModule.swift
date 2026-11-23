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
    Constant("hasShiftReturnShortcut") { true }
    Constant("hasModifiedLetterShortcuts") { true }
    Constant("hasWebBrowser") { true }
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
      AsyncFunction("openWebLink") { (view: PhoneTerminalView, frame: String, url: String, external: Bool, promise: Promise) in
        guard let presenter = self.appContext?.utilities?.currentViewController() else { promise.resolve(false); return }
        view.openWebLink(url, frame: frame, external: external, from: presenter) { promise.resolve($0) }
      }.runOnQueue(.main)
      Prop("connection") { (view: PhoneTerminalView, config: [String: String]) in view.configure(config) }
      Prop("commandHyper") { (view: PhoneTerminalView, enabled: Bool) in view.terminal.commandHyper = enabled }
      Prop("minimumColumns") { (view: PhoneTerminalView, columns: Int) in
        view.minimumColumns = (40...240).contains(columns) ? columns : 0
      }
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
    View(PhoneKeyboardContainer.self) {
      ViewName("PhoneKeyboardContainer")
      Events("onShiftReturn", "onModifiedKey")
      Prop("active") { (view: PhoneKeyboardContainer, active: Bool) in view.active = active }
    }
  }
}

// WebKit can discard Shift before delivering a hardware key to the field.
private final class PhoneKeyboardContainer: ExpoView {
  let onShiftReturn = EventDispatcher()
  let onModifiedKey = EventDispatcher()
  var active = false
  private lazy var shiftReturn: UIKeyCommand = {
    let command = UIKeyCommand(input: "\r", modifierFlags: .shift, action: #selector(sendShiftReturn))
    command.wantsPriorityOverSystemBehavior = true
    return command
  }()

  private lazy var modifiedKeys: [UIKeyCommand] = {
    let letters = "abcdefghijklmnopqrstuvwxyz".map {
      UIKeyCommand(input: String($0), modifierFlags: [.control, .shift], action: #selector(sendModifiedKey))
    }
    let colon = UIKeyCommand(input: ";", modifierFlags: [.alternate, .shift], action: #selector(sendModifiedKey))
    let keys = letters + [colon]
    for key in keys { key.wantsPriorityOverSystemBehavior = true }
    return keys
  }()

  override var keyCommands: [UIKeyCommand]? { (super.keyCommands ?? []) + [shiftReturn] + modifiedKeys }

  private func focusedView(in view: UIView) -> UIView? {
    if view.isFirstResponder { return view }
    for child in view.subviews {
      if let focused = focusedView(in: child) { return focused }
    }
    return nil
  }

  override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
    if action == #selector(sendShiftReturn) || action == #selector(sendModifiedKey) {
      guard active, let focused = focusedView(in: self) else { return false }
      return (focused as? UITextInput)?.markedTextRange == nil
    }
    return super.canPerformAction(action, withSender: sender)
  }

  @objc private func sendShiftReturn(_ sender: UIKeyCommand) { onShiftReturn() }
  @objc private func sendModifiedKey(_ sender: UIKeyCommand) {
    if sender.modifierFlags == [.alternate, .shift] { onModifiedKey(["text": "\u{1b}:"]) }
    else if let letter = sender.input?.lowercased().first?.asciiValue {
      onModifiedKey(["text": "\u{1b}[\(letter);6u"])
    }
  }
}

final class EmacsTerminalView: TerminalView {
  var commandHyper = false

  private func hyperSequence(for key: UIKey) -> String? {
    let flags = key.modifierFlags
    var modifier = 17
    if flags.contains(.shift) { modifier += 1 }
    if flags.contains(.alternate) { modifier += 2 }
    if flags.contains(.control) { modifier += 4 }
    let usage = Int(key.keyCode.rawValue)
    let suffixes = ["P", "Q", "R", "S"]
    if (0x3a...0x3d).contains(usage) { return "\u{1b}[1;\(modifier)\(suffixes[usage - 0x3a])" }
    if (0x3e...0x45).contains(usage) {
      let codes = [15, 17, 18, 19, 20, 21, 23, 24]
      return "\u{1b}[\(codes[usage - 0x3e]);\(modifier)~"
    }
    switch key.keyCode {
    case .keyboardUpArrow: return "\u{1b}[1;\(modifier)A"
    case .keyboardDownArrow: return "\u{1b}[1;\(modifier)B"
    case .keyboardRightArrow: return "\u{1b}[1;\(modifier)C"
    case .keyboardLeftArrow: return "\u{1b}[1;\(modifier)D"
    case .keyboardHome: return "\u{1b}[1;\(modifier)H"
    case .keyboardEnd: return "\u{1b}[1;\(modifier)F"
    case .keyboardInsert: return "\u{1b}[2;\(modifier)~"
    case .keyboardDeleteForward: return "\u{1b}[3;\(modifier)~"
    case .keyboardPageUp: return "\u{1b}[5;\(modifier)~"
    case .keyboardPageDown: return "\u{1b}[6;\(modifier)~"
    case .keyboardReturnOrEnter, .keypadEnter: return "\u{1b}[13;\(modifier)u"
    case .keyboardTab: return "\u{1b}[9;\(modifier)u"
    case .keyboardEscape: return "\u{1b}[27;\(modifier)u"
    case .keyboardDeleteOrBackspace: return "\u{1b}[127;\(modifier)u"
    default: break
    }
    let base = key.charactersIgnoringModifiers.lowercased()
    guard base.unicodeScalars.count == 1, let scalar = base.unicodeScalars.first else { return nil }
    var code = scalar.value
    if flags.contains(.shift), !(97...122).contains(code) {
      if let shifted = key.characters.unicodeScalars.first, (32...126).contains(shifted.value) {
        code = shifted.value
      }
      modifier -= 1
    }
    return (32...126).contains(code) ? "\u{1b}[\(code);\(modifier)u" : nil
  }

  override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    guard optionAsMetaKey, markedTextRange == nil, getTerminal().keyboardEnhancementFlags.isEmpty else {
      super.pressesBegan(presses, with: event)
      return
    }
    var remaining = presses
    for press in presses {
      guard let key = press.key else { continue }
      let modifiers = key.modifierFlags.intersection([.control, .alternate, .shift, .command])
      if commandHyper, modifiers.contains(.command), let sequence = hyperSequence(for: key) {
        send(txt: sequence)
        remaining.remove(press)
        continue
      }
      if modifiers == .shift && (key.keyCode == .keyboardReturnOrEnter || key.keyCode == .keypadEnter) {
        send(txt: "\u{1b}[27;2;13~")
        remaining.remove(press)
        continue
      }
      if modifiers == [.control, .shift],
         let letter = key.charactersIgnoringModifiers.lowercased().first?.asciiValue, (97...122).contains(letter) {
        send(txt: "\u{1b}[\(letter);6u")
        remaining.remove(press)
        continue
      }
      if !modifiers.contains(.command), !modifiers.contains(.alternate),
         !modifiers.intersection([.shift, .control]).isEmpty,
         key.keyCode == .keyboardDeleteOrBackspace || key.keyCode == .keyboardEscape {
        let code = key.keyCode == .keyboardEscape ? 27 : 127
        let modifier = 1 + (modifiers.contains(.shift) ? 1 : 0) + (modifiers.contains(.control) ? 4 : 0)
        send(txt: "\u{1b}[\(code);\(modifier)u")
        remaining.remove(press)
        continue
      }
      guard modifiers == [.alternate, .shift] else { continue }
      let symbol: String
      switch key.charactersIgnoringModifiers {
      case ",": symbol = "<"
      case ".": symbol = ">"
      case ";", ":": symbol = ":"
      default: continue
      }
      send(txt: "\u{1b}" + symbol)
      remaining.remove(press)
    }
    if !remaining.isEmpty { super.pressesBegan(remaining, with: event) }
  }
}

final class PhoneTerminalView: ExpoView, TerminalViewDelegate {
  private let browser = PhoneBrowser()
  let terminal = EmacsTerminalView(frame: .zero)
  let onSessionStatus = EventDispatcher()
  private var configuration: [String: String] = [:]
  private var connection: Task<Void, Never>?
  private var session: TerminalSession?
  private var writes: Task<Void, Never>?
  private var pendingBytes = 0
  private var generation = UUID()
  private var rows = 24
  private var columns = 80
  var minimumColumns = 120 {
    didSet { if minimumColumns != oldValue { setNeedsLayout() } }
  }

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
    guard bounds.width > 0, bounds.height > 0 else { return }
    let cellWidth = terminal.getOptimalFrameSize().width / CGFloat(max(1, terminal.getTerminal().cols))
    let width = max(bounds.width, ceil(CGFloat(minimumColumns) * cellWidth))
    let scale = bounds.width / width
    // SwiftTerm derives the SSH PTY and the reviewable rows from these bounds.
    terminal.bounds.size = CGSize(width: width, height: bounds.height / scale)
    terminal.transform = CGAffineTransform(scaleX: scale, y: scale)
    terminal.center = CGPoint(x: bounds.midX, y: bounds.midY)
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
    if window == nil {
      // Full-screen Safari temporarily removes the presenting hierarchy.
      if !browser.coversTerminal { close() }
    }
    else if connection == nil && session == nil { start() }
  }

  override func didMoveToSuperview() {
    super.didMoveToSuperview()
    if superview == nil { close() }
  }

  deinit {
    connection?.cancel()
    writes?.cancel()
    if let session { Task { try? await session.disconnect() } }
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
    let owner = generation, initialColumns = columns, initialRows = rows
    connection = Task { @MainActor [weak self] in
      do {
        let size = try TerminalSize(columns: initialColumns, rows: initialRows)
        let live = try await PhoneIdentity.connect(host: host, port: port, username: user, pin: pin,
          server: server, client: client, frame: frame, size: size) { [weak self] bytes in
          DispatchQueue.main.async {
            guard let self, self.generation == owner else { return }
            self.terminal.feed(byteArray: bytes[...])
          }
        }
        do {
          guard let self, generation == owner else { try? await live.disconnect(); return }
          session = live
          try await live.resize(TerminalSize(columns: columns, rows: rows))
          guard generation == owner else { return }
          onSessionStatus(["state":"connected", "frame":frame])
        }
        let exit = try await live.waitForExit()
        if let self, generation == owner {
          close()
          onSessionStatus(["state":"closed", "frame":frame, "retryable":exit == .disconnected])
        }
      } catch {
        if let self, generation == owner {
          let reason: String
          let retryable: Bool
          switch error {
          case TerminalError.hostKeyMismatch: reason = "The SSH host key does not match."; retryable = false
          case TerminalError.keyRejected: reason = "WSL rejected the iPhone public key."; retryable = false
          case TerminalError.invalidDestination, TerminalError.invalidSize, TerminalError.requestRejected:
            reason = "Could not open the SSH terminal."; retryable = false
          default: reason = "The SSH connection was interrupted."; retryable = true
          }
          close()
          onSessionStatus(["state":"failed", "frame":frame, "detail":reason, "retryable":retryable])
        }
      }
    }
  }

  func sendKeys(_ text: String, to frame: String) {
    guard terminal.isUserInteractionEnabled, configuration["frame"] == frame,
          !text.isEmpty, text.utf8.count <= 1024 else { return }
    send(source: terminal, data: Array(text.utf8)[...])
  }

  func openWebLink(_ url: String, frame: String, external: Bool, from presenter: UIViewController, done: @escaping (Bool) -> Void) {
    guard window != nil, configuration["frame"] == frame, session != nil else { done(false); return }
    browser.open(url, external: external, from: presenter, done: done)
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
      catch { if generation == owner { close(); onSessionStatus(["state":"closed", "frame":frame, "retryable":true]) }; return }
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
