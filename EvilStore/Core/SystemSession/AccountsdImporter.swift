// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import Foundation

/// path A: read the active iCloud / iTunes account through ACAccountStore.
///
/// requires private entitlements:
///   com.apple.accounts.appleaccount.fullaccess
///   com.apple.private.accounts.bundleidspoofing  (some ios versions)
final class AccountsdImporter: SystemSessionImporter {
    let name = "accountsd"

    func isAvailable() async -> Bool {
        ESAccountsdBridge.isAvailable()
    }

    func snapshot() async throws -> Account {
        var lastError: Error?
        if let acc = try? snapshotFromAppleID() {
            return acc
        }
        // some devices only expose iTunesStore type
        do {
            return try snapshotFromiTunes()
        } catch {
            lastError = error
        }
        if let lastError {
            throw lastError
        }
        throw SystemSessionError.notLoggedIn
    }

    // MARK: - paths

    private func snapshotFromAppleID() throws -> Account {
        guard let dict = ESAccountsdBridge.copyAppleIDAccountInfo() else {
            throw mapError(ESAccountsdBridge.lastFailureReason)
        }
        return try buildAccount(from: dict)
    }

    private func snapshotFromiTunes() throws -> Account {
        guard let dict = ESAccountsdBridge.copyiTunesStoreAccountInfo() else {
            throw mapError(ESAccountsdBridge.lastFailureReason)
        }
        return try buildAccount(from: dict)
    }

    // MARK: - mapping

    private func buildAccount(from dict: [String: String]) throws -> Account {
        // dsid is the only field accountsd reliably provides. storefront often
        // lives in StoreKit (path D); guid is per-device, so we mint our own
        // when no importer has it. cookies come from filesystem.
        guard let dsid = dict["dsid"] else {
            throw SystemSessionError.fileFormatChanged(path: "accountsd:dsid")
        }
        let storefront = storefrontHead(dict["storefront"] ?? "")
        return Account(
            source: .systemBorrowed,
            email: dict["email"] ?? "",
            firstName: "",
            lastName: "",
            directoryServicesIdentifier: dsid,
            passwordToken: dict["oauthToken"],
            storefront: storefront,
            pod: nil,
            guid: "",
            cookies: [],
            encryptedPassword: nil
        )
    }

    private func storefrontHead(_ raw: String) -> String {
        raw.split(separator: "-").first.map(String.init) ?? raw
    }

    private func mapError(_ reason: String?) -> Error {
        guard let reason else { return SystemSessionError.notLoggedIn }
        if reason.hasPrefix("no accounts") {
            return SystemSessionError.notLoggedIn
        }
        return SystemSessionError.entitlementDenied(reason)
    }
}
