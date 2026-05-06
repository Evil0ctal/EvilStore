// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import Foundation

/// runs every strategy and **merges** their partial Account results. each
/// path contributes whatever fields it can — accountsd typically gives
/// dsid + email, storekit gives storefront, filesystem gives cookies +
/// (sometimes) guid + token. the first non-empty value across paths wins.
///
/// throws `.allPathsFailed` only when every strategy threw.
final class CompositeImporter: SystemSessionImporter {
    let name = "composite"
    private let strategies: [SystemSessionImporter]

    init(strategies: [SystemSessionImporter]) {
        self.strategies = strategies
    }

    func isAvailable() async -> Bool {
        for s in strategies where await s.isAvailable() {
            return true
        }
        return false
    }

    func snapshot() async throws -> Account {
        var collected: [Account] = []
        var failures: [String] = []
        for s in strategies {
            do {
                let acc = try await s.snapshot()
                NSLog("[EvilStore] stealth path %@: ok", s.name)
                collected.append(acc)
            } catch {
                let line = "\(s.name): \(error)"
                NSLog("[EvilStore] stealth path %@", line)
                failures.append(line)
            }
        }

        guard !collected.isEmpty else {
            throw SystemSessionError.allPathsFailed(failures)
        }

        let merged = merge(collected)
        // dsid is the only field every storefront call needs; without it we
        // genuinely cannot reach the private API.
        guard !merged.directoryServicesIdentifier.isEmpty else {
            throw SystemSessionError.notLoggedIn
        }
        return merged
    }

    /// fold partial Accounts together. preserves the first non-empty value
    /// for each field across the strategy order.
    private func merge(_ accounts: [Account]) -> Account {
        var result = accounts[0]
        for next in accounts.dropFirst() {
            if result.email.isEmpty { result.email = next.email }
            if result.firstName.isEmpty { result.firstName = next.firstName }
            if result.lastName.isEmpty { result.lastName = next.lastName }
            if result.directoryServicesIdentifier.isEmpty {
                result.directoryServicesIdentifier = next.directoryServicesIdentifier
            }
            if result.passwordToken == nil { result.passwordToken = next.passwordToken }
            if result.storefront.isEmpty { result.storefront = next.storefront }
            if result.pod == nil { result.pod = next.pod }
            if result.guid.isEmpty { result.guid = next.guid }
            if result.cookies.isEmpty { result.cookies = next.cookies }
        }
        return result
    }
}
