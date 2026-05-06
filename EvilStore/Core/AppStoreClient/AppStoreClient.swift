// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import Foundation

/// public surface for everything storefront-related. M1 implements only the
/// auth-free pieces (lookup + search); list-versions, purchase, download land
/// in M2+ once the system-session importer ships a real Account.
protocol AppStoreClient {
    func search(term: String, country: String, limit: Int) async throws -> [App]
    func lookup(bundleID: String, country: String) async throws -> App
}

/// production implementation. holds one HTTPClient (and therefore one
/// AsyncThrottle gate) for all storefront calls.
struct AppStoreClientLive: AppStoreClient {
    private let http: HTTPClient

    init(http: HTTPClient = URLSessionHTTPClient()) {
        self.http = http
    }

    func search(term: String, country: String, limit: Int) async throws -> [App] {
        try await Search.apps(term: term, country: country, limit: limit, client: http)
    }

    func lookup(bundleID: String, country: String) async throws -> App {
        try await Lookup.byBundleID(bundleID, country: country, client: http)
    }
}
