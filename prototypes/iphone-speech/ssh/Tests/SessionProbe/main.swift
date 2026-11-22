// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later

import Crypto
import EmacsTerminalSSH
import Foundation
import NIOPosix

// This executable is the WSL test driver. Report events without logging terminal text.
private final class Display: @unchecked Sendable {
    private let lock = NSLock()
    private var seen = false

    func receive(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        if !seen {
            seen = true
            report("display")
        }
    }
}

private func report(_ message: String) {
    FileHandle.standardOutput.write(Data((message + "\n").utf8))
}

private enum ProbeError: Error { case arguments, malformedInput }

private func run() async throws {
    let args = Array(CommandLine.arguments.dropFirst())
    guard args.count >= 2 else { throw ProbeError.arguments }
    let seed = try Data(contentsOf: URL(fileURLWithPath: args[1]))
    let key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
    if args[0] == "public-key" {
        report(TerminalSession.publicKey(for: key))
        return
    }
    guard (7...8).contains(args.count), args[0] == "connect", let port = Int(args[2]) else { throw ProbeError.arguments }
    let pin = try String(contentsOfFile: args[4], encoding: .utf8)
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    do {
        let display = Display()
        let session = try await TerminalSession.connect(host: "127.0.0.1", port: port, username: args[3],
            pinnedHostKey: pin, identity: key, server: args[5], emacsclient: args[6], phoneFrame: args.count == 8 ? args[7] : nil,
            size: TerminalSize(columns: 80, rows: 24), group: group, output: { display.receive($0) })
        report("ready")
        while let line = readLine() {
            let parts = line.split(separator: " ")
            if parts.count == 2, parts[0] == "input", let data = Data(base64Encoded: String(parts[1])) {
                try await session.send(Array(data))
            } else if parts.count == 3, parts[0] == "resize", let cols = Int(parts[1]), let rows = Int(parts[2]) {
                try await session.resize(TerminalSize(columns: cols, rows: rows))
            } else if line == "wait" {
                report("exit \(try await session.waitForExit())")
                break
            } else if line == "disconnect" { break }
            else { throw ProbeError.malformedInput }
        }
        try await session.disconnect()
    } catch {
        try await group.shutdownGracefully()
        throw error
    }
    try await group.shutdownGracefully()
}

do { try await run() }
catch {
    if let failure = error as? TerminalError { report("error \(failure)") }
    else { report("error \(type(of: error))") }
    exit(1)
}
