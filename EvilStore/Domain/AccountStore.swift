// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import Foundation

/// app-wide holder of the active borrowed Account. populated at launch by
/// CompositeImporter walking the four stealth paths. UI binds via
/// @EnvironmentObject so views know whether the private storefront is
/// reachable yet.
@MainActor
final class AccountStore: ObservableObject {
    enum ProbeState: Equatable {
        case idle
        case probing
        case ready
        case noSession
        case failed(String)
    }

    @Published private(set) var active: Account?
    @Published private(set) var state: ProbeState = .idle

    private let importer: SystemSessionImporter

    init(importer: SystemSessionImporter? = nil) {
        self.importer = importer ?? CompositeImporter(strategies: [
            AccountsdImporter(),
            FileSystemImporter(),
            KeychainImporter()
        ])
    }

    /// safe to call multiple times; reuses the cached account if probing
    /// already produced one.
    func bootstrap() async {
        guard active == nil, state != .probing else { return }
        state = .probing
        do {
            let acc = try await importer.snapshot()
            active = acc
            state = .ready
        } catch let err as SystemSessionError {
            state = mapState(err)
        } catch {
            state = .failed("\(error)")
        }
    }

    /// hand-import (manual login flow lands later); for now lets diagnostics
    /// or future M3 paths inject without re-walking the importer chain.
    func setActive(_ account: Account) {
        active = account
        state = .ready
    }

    private func mapState(_ err: SystemSessionError) -> ProbeState {
        switch err {
        case .notLoggedIn:
            return .noSession
        case let .entitlementDenied(reason):
            return .failed("entitlement denied: \(reason)")
        case let .fileFormatChanged(path):
            return .failed("file format unexpected at \(path)")
        case .tokenDecryptionFailed:
            return .failed("token decryption failed")
        case let .allPathsFailed(reasons):
            return .failed("all stealth paths failed: \(reasons.joined(separator: ", "))")
        }
    }
}
