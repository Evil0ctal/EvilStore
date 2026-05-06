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
    private let vault: KeychainVault

    init(
        importer: SystemSessionImporter? = nil,
        vault: KeychainVault = KeychainVaultLive()
    ) {
        self.importer = importer ?? CompositeImporter(strategies: [
            AccountsdImporter(),
            StoreKitImporter(),
            FileSystemImporter(),
            KeychainImporter()
        ])
        self.vault = vault
    }

    /// reuses the cached account if probing already produced one. pass
    /// `force: true` from the Settings re-probe button to bypass the cache.
    func bootstrap(force: Bool = false) async {
        if !force {
            guard active == nil, state != .probing else { return }
        } else {
            active = nil
        }
        state = .probing
        NSLog("[EvilStore] stealth: bootstrap start (force=%@)", force ? "yes" : "no")
        do {
            var acc = try await importer.snapshot()
            // every importer can return empty fields; we backfill here so the
            // resulting Account is usable by AppStoreClient regardless of which
            // path landed it.
            if acc.guid.isEmpty {
                acc.guid = persistedGuid()
            }
            active = acc
            state = .ready
            NSLog(
                "[EvilStore] stealth: ready — storefront=%@ guid=%@ token=%@ cookies=%d",
                acc.storefront.isEmpty ? "(empty)" : acc.storefront,
                acc.guid.isEmpty ? "(empty)" : "(\(acc.guid.count) chars)",
                acc.passwordToken.map { _ in "present" } ?? "nil",
                acc.cookies.count
            )
        } catch let err as SystemSessionError {
            state = mapState(err)
            NSLog("[EvilStore] stealth: failed — %@", "\(err)")
        } catch {
            state = .failed("\(error)")
            NSLog("[EvilStore] stealth: failed (unknown) — %@", "\(error)")
        }
    }

    // MARK: - guid persistence

    private static let guidKey = "device.guid"

    /// returns a stable 12-hex GUID. minted on first call, persisted in the
    /// keychain so reinstalls don't look like new devices to apple risk
    /// control. matches the ApplePackage.DeviceIdentifier convention.
    private func persistedGuid() -> String {
        if let existing = (try? vault.getString(Self.guidKey)) ?? nil,
           existing.count == 12
        {
            return existing
        }
        let fresh = generateGuid()
        try? vault.setString(fresh, for: Self.guidKey)
        return fresh
    }

    private func generateGuid() -> String {
        let chars = Array("0123456789ABCDEF")
        return String((0 ..< 12).map { _ in chars.randomElement()! })
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
