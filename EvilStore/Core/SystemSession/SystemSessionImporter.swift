// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import Foundation

enum SystemSessionError: Error, Equatable {
    case notLoggedIn
    case entitlementDenied(String)
    case fileFormatChanged(path: String)
    case tokenDecryptionFailed
    case allPathsFailed([String])
}

protocol SystemSessionImporter {
    /// short identifier shown in diagnostics, e.g. "accountsd", "filesystem", "keychain"
    var name: String { get }
    /// cheap availability probe; do not return false on transient io errors
    func isAvailable() async -> Bool
    /// returns an Account ready to be passed to AppStoreClient
    func snapshot() async throws -> Account
}
