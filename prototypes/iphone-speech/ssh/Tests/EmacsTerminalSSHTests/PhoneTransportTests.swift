// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import NIOCore
import NIOPosix
import XCTest
@testable import EmacsTerminalSSH

private struct TestResolver: Resolver, Sendable {
    let loop: EventLoop

    func initiateAQuery(host: String, port: Int) -> EventLoopFuture<[SocketAddress]> {
        guard host == "wsl.test" else { return loop.makeFailedFuture(URLError(.cannotFindHost)) }
        return loop.makeCompletedFuture { [try SocketAddress(ipAddress: "127.0.0.1", port: port)] }
    }

    func initiateAAAAQuery(host: String, port: Int) -> EventLoopFuture<[SocketAddress]> {
        loop.makeSucceededFuture([])
    }

    func cancelQueries() {}
}

final class PhoneTransportTests: XCTestCase {
    func testSavedAddressCanReachListenerWhenOnlyHostnamesResolve() throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }
        let server = try ServerBootstrap(group: group)
            .bind(to: SocketAddress(ipAddress: "127.0.0.1", port: 0)).wait()
        defer { try? server.close().wait() }
        let port = try XCTUnwrap(server.localAddress?.port)
        let client = ClientBootstrap(group: group).resolver(TestResolver(loop: group.next()))
        func connect(_ host: String, phone: Bool) throws {
            let channel = try TerminalSession.openTransport(client, host: host, port: port, phone: phone).wait()
            try channel.close().wait()
        }

        XCTAssertThrowsError(try connect("127.0.0.1", phone: false))
        try connect("127.0.0.1", phone: true)
        try connect("wsl.test", phone: true)
        try connect("wsl.test", phone: false)
    }
}
