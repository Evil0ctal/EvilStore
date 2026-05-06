// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import Foundation
import Security

/// minimal keychain helper. one item per (service, account) tuple, generic
/// password class, app-default access group. used by AccountStore for the
/// device GUID fallback so a re-install does not look like a new device to
/// apple's risk control.
protocol KeychainVault {
    func set(_ data: Data, for key: String) throws
    func get(_ key: String) throws -> Data?
    func remove(_ key: String) throws
}

extension KeychainVault {
    func setString(_ value: String, for key: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainVaultError.encoding
        }
        try set(data, for: key)
    }

    func getString(_ key: String) throws -> String? {
        guard let data = try get(key) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

enum KeychainVaultError: Error, Equatable {
    case status(OSStatus)
    case encoding
}

final class KeychainVaultLive: KeychainVault {
    private let service: String

    init(service: String = "com.evil0ctal.evilstore") {
        self.service = service
    }

    func set(_ data: Data, for key: String) throws {
        let baseQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]
        // try update first
        let attrs: [CFString: Any] = [kSecValueData: data]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attrs as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus != errSecItemNotFound {
            throw KeychainVaultError.status(updateStatus)
        }

        var add = baseQuery
        add[kSecValueData] = data
        add[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainVaultError.status(addStatus)
        }
    }

    func get(_ key: String) throws -> Data? {
        let q: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainVaultError.status(status) }
        return out as? Data
    }

    func remove(_ key: String) throws {
        let q: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]
        let status = SecItemDelete(q as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound { return }
        throw KeychainVaultError.status(status)
    }
}
