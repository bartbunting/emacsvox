// swift-tools-version: 6.1
// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later
import PackageDescription

let package = Package(
    name: "EmacsTerminalSSH",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "EmacsTerminalSSH", targets: ["EmacsTerminalSSH"])],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio-ssh.git", exact: "0.15.1"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.81.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0"..<"6.0.0"),
    ],
    targets: [
        .target(name: "EmacsTerminalSSH", dependencies: [
            .product(name: "NIOSSH", package: "swift-nio-ssh"),
            .product(name: "NIOCore", package: "swift-nio"),
            .product(name: "NIOPosix", package: "swift-nio"),
            .product(name: "Crypto", package: "swift-crypto"),
        ]),
        .executableTarget(name: "SessionProbe", dependencies: ["EmacsTerminalSSH",
            .product(name: "Crypto", package: "swift-crypto"),
            .product(name: "NIOPosix", package: "swift-nio"),
        ], path: "Tests/SessionProbe"),
        .testTarget(name: "EmacsTerminalSSHTests", dependencies: ["EmacsTerminalSSH",
            .product(name: "NIOCore", package: "swift-nio"),
            .product(name: "NIOPosix", package: "swift-nio"),
        ]),
    ]
)
