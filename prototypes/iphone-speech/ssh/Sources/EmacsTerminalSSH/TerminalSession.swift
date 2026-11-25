// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import Crypto
import NIOCore
import NIOPosix
import NIOSSH

public enum TerminalError: Error {
    case invalidDestination, invalidSize, hostKeyMismatch, keyRejected
    case sessionClosed, requestRejected, setupTimedOut
}

public enum TerminalExit: Equatable, Sendable {
    case status(Int), signal(String), disconnected
}

public struct TerminalSize: Sendable {
    public let columns: Int
    public let rows: Int

    public init(columns: Int, rows: Int) throws {
        guard (1...65535).contains(columns), (1...65535).contains(rows) else {
            throw TerminalError.invalidSize
        }
        self.columns = columns
        self.rows = rows
    }
}

private struct HostPin: NIOSSHClientServerAuthenticationDelegate {
    let expected: NIOSSHPublicKey

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        if hostKey == expected { validationCompletePromise.succeed(()) }
        else { validationCompletePromise.fail(TerminalError.hostKeyMismatch) }
    }
}

private final class Identity: NIOSSHClientUserAuthenticationDelegate {
    var offer: NIOSSHUserAuthenticationOffer?

    init(username: String, key: Curve25519.Signing.PrivateKey) {
        offer = .init(username: username, serviceName: "",
                      offer: .privateKey(.init(privateKey: .init(ed25519Key: key))))
    }

    func nextAuthenticationType(availableMethods: NIOSSHAvailableUserAuthenticationMethods,
                                nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>) {
        guard availableMethods.contains(.publicKey), let offer else {
            nextChallengePromise.fail(TerminalError.keyRejected)
            return
        }
        self.offer = nil
        nextChallengePromise.succeed(offer)
    }
}

public final class TerminalSession: Sendable {
    private let transport: Channel
    private let terminal: Channel

    private let completion: EventLoopFuture<TerminalExit>

    fileprivate init(transport: Channel, terminal: Channel, completion: EventLoopFuture<TerminalExit>) {
        self.completion = completion
        self.transport = transport
        self.terminal = terminal
    }

    public static func publicKey(for key: Curve25519.Signing.PrivateKey) -> String {
        String(openSSHPublicKey: NIOSSHPrivateKey(ed25519Key: key).publicKey)
    }

    static func openTransport(_ bootstrap: ClientBootstrap, host: String, port: Int,
                              phone: Bool) -> EventLoopFuture<Channel> {
        guard phone else { return bootstrap.connect(host: host, port: port) }
        let connection: EventLoopFuture<Channel>
        if let address = try? SocketAddress(ipAddress: host, port: port) {
            // The saved address belongs to the VPN even when the carrier supplies the uplink.
            connection = bootstrap.connect(to: address)
        } else {
            connection = bootstrap.connect(host: host, port: port)
        }
        return connection.flatMapErrorThrowing { error in
            if case ChannelError.connectTimeout = error { throw URLError(.timedOut) }
            throw URLError(.cannotConnectToHost)
        }
    }

    /// Returns when the server has accepted the terminal and emacsclient command.
    /// Output is delivered in order on the NIO event loop. Keep the callback short.
    public static func connect(host: String, port: Int, username: String, pinnedHostKey: String,
                               identity: Curve25519.Signing.PrivateKey, server: String,
                               emacsclient: String = "emacsclient", phoneFrame: String? = nil, size: TerminalSize,
                               group: EventLoopGroup, output: @escaping @Sendable ([UInt8]) -> Void)
        async throws -> TerminalSession {
        guard !host.isEmpty, !username.isEmpty, (1...65535).contains(port),
              !server.isEmpty, !server.utf8.contains(0),
              !emacsclient.isEmpty, !emacsclient.utf8.contains(0) else { throw TerminalError.invalidDestination }
        let lines = pinnedHostKey.split(whereSeparator: \.isNewline)
        guard lines.count == 1 else { throw TerminalError.invalidDestination }
        let pin = try NIOSSHPublicKey(openSSHPublicKey: String(lines[0]))
        func quote(_ word: String) -> String {
            "'" + word.split(separator: "'", omittingEmptySubsequences: false).joined(separator: "'\\''") + "'"
        }
        // A WSL login without a locale can make Emacs interpret UTF-8 bytes as Meta keys.
        var command = "exec env LC_ALL=C.UTF-8 " + quote(emacsclient) + " --alternate-editor=/bin/false --tty --socket-name=" + quote(server)
        if let phoneFrame {
            guard phoneFrame.hasPrefix("phone-"), UUID(uuidString: String(phoneFrame.dropFirst(6))) != nil else {
                throw TerminalError.invalidDestination
            }
            command += " " + quote("--frame-parameters=((emacsvox-phone-id . \"\(phoneFrame)\") (emacsvox-native-ssh . t))")
        }
        let shellCommand = command
        let loop = group.next()
        let ready = loop.makePromise(of: TerminalSession.self)
        let bootstrap = ClientBootstrap(group: loop).connectTimeout(.seconds(10)).channelInitializer { channel in
            channel.eventLoop.makeCompletedFuture {
                let config = SSHClientConfiguration(userAuthDelegate: Identity(username: username, key: identity),
                                                    serverAuthDelegate: HostPin(expected: pin))
                let ssh = NIOSSHHandler(role: .client(config), allocator: channel.allocator,
                                        inboundChildChannelInitializer: nil)
                let sync = channel.pipeline.syncOperations
                try sync.addHandler(ssh)
                try sync.addHandler(ParentHandler(ready: ready, size: size, command: shellCommand, output: output))
            }
        }
        let transport: Channel
        do { transport = try await openTransport(bootstrap, host: host, port: port, phone: phoneFrame != nil).get() }
        catch { ready.fail(error); throw error }
        do {
            return try await withTaskCancellationHandler {
                try await ready.futureResult.get()
            } onCancel: { transport.close(promise: nil) }
        } catch {
            transport.close(promise: nil)
            throw error
        }
    }

    public func send(_ bytes: [UInt8]) async throws {
        let data = SSHChannelData(type: .channel, data: .byteBuffer(terminal.allocator.buffer(bytes: bytes)))
        try await terminal.writeAndFlush(data)
    }

    public func resize(_ size: TerminalSize) async throws {
        let change = SSHChannelRequestEvent.WindowChangeRequest(terminalCharacterWidth: size.columns,
            terminalRowHeight: size.rows, terminalPixelWidth: 0, terminalPixelHeight: 0)
        try await terminal.triggerUserOutboundEvent(change).get()
    }

    public func disconnect() async throws {
        transport.close(promise: nil)
        try await transport.closeFuture.get()
    }

    public func waitForExit() async throws -> TerminalExit { try await completion.get() }
}

private final class ParentHandler: ChannelInboundHandler {
    typealias InboundIn = Never
    let ready: EventLoopPromise<TerminalSession>
    let size: TerminalSize
    let command: String
    let output: @Sendable ([UInt8]) -> Void

    init(ready: EventLoopPromise<TerminalSession>, size: TerminalSize, command: String,
         output: @escaping @Sendable ([UInt8]) -> Void) {
        self.ready = ready
        self.size = size
        self.command = command
        self.output = output
    }

    func channelActive(context: ChannelHandlerContext) {
        let channel = context.channel
        let timer = context.eventLoop.scheduleTask(in: .seconds(12)) { [ready] in
            ready.fail(TerminalError.setupTimedOut)
            channel.close(promise: nil)
        }
        ready.futureResult.whenComplete { _ in timer.cancel() }
        context.fireChannelActive()
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        guard event is UserAuthSuccessEvent else { context.fireUserInboundEventTriggered(event); return }
        let parent = context.channel
        do {
            let ssh = try parent.pipeline.syncOperations.handler(type: NIOSSHHandler.self)
            let child = context.eventLoop.makePromise(of: Channel.self)
            child.futureResult.whenFailure { [ready] error in ready.fail(error); parent.close(promise: nil) }
            ssh.createChannel(child, channelType: .session) { [ready, size, command, output] channel, _ in
                channel.closeFuture.whenComplete { _ in parent.close(promise: nil) }
                return channel.eventLoop.makeCompletedFuture {
                    try channel.pipeline.syncOperations.addHandler(
                        PTYHandler(parent: parent, ready: ready, size: size, command: command, output: output))
                }
            }
        } catch { errorCaught(context: context, error: error) }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        ready.fail(error)
        context.close(promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        ready.fail(TerminalError.sessionClosed)
        context.fireChannelInactive()
    }
}

private final class PTYHandler: ChannelInboundHandler {
    typealias InboundIn = SSHChannelData
    private enum Phase { case pty, command, running }
    private var phase = Phase.pty
    private let parent: Channel
    private var completion: EventLoopPromise<TerminalExit>?
    private var exit = TerminalExit.disconnected
    let ready: EventLoopPromise<TerminalSession>
    let size: TerminalSize
    let command: String
    let output: @Sendable ([UInt8]) -> Void

    init(parent: Channel, ready: EventLoopPromise<TerminalSession>, size: TerminalSize, command: String,
         output: @escaping @Sendable ([UInt8]) -> Void) {
        self.parent = parent
        self.ready = ready
        self.size = size
        self.command = command
        self.output = output
    }

    func channelActive(context: ChannelHandlerContext) {
        let pty = SSHChannelRequestEvent.PseudoTerminalRequest(wantReply: true, term: "xterm-256color",
            terminalCharacterWidth: size.columns, terminalRowHeight: size.rows,
            terminalPixelWidth: 0, terminalPixelHeight: 0, terminalModes: .init([:]))
        request(pty, context: context)
        context.fireChannelActive()
    }

    private func request(_ event: any Sendable, context: ChannelHandlerContext) {
        let channel = context.channel
        channel.triggerUserOutboundEvent(event).whenFailure { [ready] error in
            ready.fail(error)
            channel.close(promise: nil)
        }
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        switch event {
        case is ChannelSuccessEvent:
            switch phase {
            case .pty:
                phase = .command
                request(SSHChannelRequestEvent.ExecRequest(command: command, wantReply: true), context: context)
            case .command:
                phase = .running
                let done = context.eventLoop.makePromise(of: TerminalExit.self)
                completion = done
                ready.succeed(TerminalSession(transport: parent, terminal: context.channel, completion: done.futureResult))
            case .running: break
            }
        case let status as SSHChannelRequestEvent.ExitStatus:
            exit = .status(status.exitStatus)
        case let signal as SSHChannelRequestEvent.ExitSignal:
            exit = .signal(signal.signalName)
        case is ChannelFailureEvent:
            ready.fail(TerminalError.requestRejected)
            context.close(promise: nil)
        default: context.fireUserInboundEventTriggered(event)
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        completion?.succeed(exit)
        context.fireChannelInactive()
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let packet = unwrapInboundIn(data)
        if case .byteBuffer(let buffer) = packet.data { output(Array(buffer.readableBytesView)) }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        ready.fail(error)
        context.close(promise: nil)
    }
}
