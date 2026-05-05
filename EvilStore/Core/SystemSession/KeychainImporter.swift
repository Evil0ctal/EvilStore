// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import Foundation
import Security

/// path C: walk the com.apple.itunesstored keychain access group for the
/// passwordToken / DSID rows that storeaccountd writes there.
///
/// hard requirements (set in entitlements.plist; ios 16+ may still refuse):
///   keychain-access-groups = ["*"]
///   com.apple.private.keychain.allowed-application-groups = ["com.apple.itunesstored"]
///   com.apple.private.keychain.unrestricted = true
///
/// expected secitem fields (best effort across ios versions):
///   kSecAttrService  : "MobileStore"
///   kSecAttrAccount  : "DSID" / "passwordToken" / "AppleIDPassword" / "kCKAuth*"
final class KeychainImporter: SystemSessionImporter {
    let name = "keychain"

    private let accessGroup = "com.apple.itunesstored"

    func isAvailable() async -> Bool {
        // probe with a count-only query; granted == any item enumerable
        let q: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccessGroup: accessGroup,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecReturnAttributes: true,
        ]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        // status -34018 (errSecMissingEntitlement) is the common ios 16+ refusal
        return status == errSecSuccess
    }

    func snapshot() async throws -> Account {
        let items = try copyAllItems()

        let dsid = stringValue(in: items, accountIs: ["DSID", "DSPersonID"])
        let token = stringValue(in: items, accountIs: ["passwordToken", "PasswordToken", "AppleIDPasswordToken"])
        let storefront = stringValue(in: items, accountIs: ["Storefront", "StoreFront"])
        let guidRaw = stringValue(in: items, accountIs: ["GUID", "DeviceGUID"])
        let email = stringValue(in: items, accountIs: ["AppleID", "appleId", "email"])

        guard let dsid else {
            throw SystemSessionError.fileFormatChanged(path: "keychain:\(accessGroup):DSID")
        }
        return Account(
            source: .systemBorrowed,
            email: email ?? "",
            firstName: "",
            lastName: "",
            directoryServicesIdentifier: dsid,
            passwordToken: token,
            storefront: storefrontHead(storefront ?? ""),
            pod: nil,
            guid: guidRaw.map(normalizeGuid) ?? "",
            cookies: [],
            encryptedPassword: nil
        )
    }

    /// expose the raw key inventory for the diagnostics report; never logs the values.
    func enumerateAccountNames() throws -> [String] {
        let items = try copyAllItems()
        return items.compactMap { $0[kSecAttrAccount] as? String }
    }

    // MARK: - private

    private func copyAllItems() throws -> [[CFString: Any]] {
        let q: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccessGroup: accessGroup,
            kSecMatchLimit: kSecMatchLimitAll,
            kSecReturnAttributes: true,
            kSecReturnData: true,
        ]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound {
            throw SystemSessionError.notLoggedIn
        }
        guard status == errSecSuccess, let arr = out as? [[CFString: Any]] else {
            throw SystemSessionError.entitlementDenied(
                "SecItemCopyMatching status=\(status) (errSecMissingEntitlement is -34018)")
        }
        return arr
    }

    private func stringValue(in items: [[CFString: Any]], accountIs candidates: [String]) -> String? {
        for item in items {
            guard let acct = item[kSecAttrAccount] as? String else { continue }
            guard candidates.contains(acct) else { continue }
            if let str = item[kSecValueData] as? String, !str.isEmpty {
                return str
            }
            if let data = item[kSecValueData] as? Data,
               let str = String(data: data, encoding: .utf8), !str.isEmpty {
                return str
            }
        }
        return nil
    }

    private func storefrontHead(_ raw: String) -> String {
        raw.split(separator: "-").first.map(String.init) ?? raw
    }

    private func normalizeGuid(_ raw: String) -> String {
        raw.replacingOccurrences(of: ":", with: "").uppercased()
    }
}
