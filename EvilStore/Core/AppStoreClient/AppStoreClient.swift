// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import Foundation

/// public surface for everything storefront-related. m1 wired up the auth-free
/// pieces (lookup + search). m2 adds listVersions which needs an Account.
/// purchase + download arrive in m3.
protocol AppStoreClient {
    func search(term: String, country: String, limit: Int) async throws -> [App]
    func lookup(bundleID: String, country: String) async throws -> App
    func listVersions(account: Account, app: App) async throws -> [String]
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

    func listVersions(account: Account, app: App) async throws -> [String] {
        try await ListVersions.run(account: account, app: app, client: http)
    }
}
