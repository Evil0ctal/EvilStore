// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import Foundation
import StoreKit

/// path D — public StoreKit. SKPaymentQueue.default().storefront has been
/// available since ios 13 and gives us the same numeric storefront id
/// ("143441" etc) that the private storefront API expects. no entitlements
/// required, no risk-control surface.
///
/// only contributes storefront. dsid + cookies + guid still come from the
/// other paths (or are generated locally).
final class StoreKitImporter: SystemSessionImporter {
    let name = "storekit"

    func isAvailable() async -> Bool {
        SKPaymentQueue.default().storefront != nil
    }

    func snapshot() async throws -> Account {
        guard let storefront = SKPaymentQueue.default().storefront else {
            throw SystemSessionError.notLoggedIn
        }
        return Account(
            source: .systemBorrowed,
            email: "",
            firstName: "",
            lastName: "",
            directoryServicesIdentifier: "",
            passwordToken: nil,
            storefront: storefront.identifier,
            pod: nil,
            guid: "",
            cookies: [],
            encryptedPassword: nil
        )
    }
}
