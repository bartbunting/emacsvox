// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later
#if os(iOS)
import Crypto
import Foundation
import NIOPosix
import Security

public enum PhoneIdentity {
    private static func key() throws -> Curve25519.Signing.PrivateKey {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: "org.emacsvox.iphone.ssh",
                                    kSecAttrAccount as String: "terminal-ed25519"]
        var lookup = query
        lookup[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecSuccess, let seed = result as? Data {
            return try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
        }
        guard status == errSecItemNotFound else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        let created = Curve25519.Signing.PrivateKey()
        var insert = query
        insert[kSecValueData as String] = created.rawRepresentation
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let saved = SecItemAdd(insert as CFDictionary, nil)
        if saved == errSecDuplicateItem { return try key() }
        guard saved == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(saved)) }
        return created
    }

    public static func publicKey() throws -> String { try TerminalSession.publicKey(for: key()) }

    public static func connect(host: String, port: Int, username: String, pin: String,
                               server: String, client: String, frame: String, size: TerminalSize,
                               output: @escaping @Sendable ([UInt8]) -> Void) async throws -> TerminalSession {
        try await TerminalSession.connect(host: host, port: port, username: username, pinnedHostKey: pin,
            identity: key(), server: server, emacsclient: client, phoneFrame: frame, size: size,
            group: MultiThreadedEventLoopGroup.singleton, output: output)
    }
}
#endif
