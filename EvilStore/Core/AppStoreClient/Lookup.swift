// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import Foundation

/// look an app up by bundle id via itunes.apple.com/lookup. public endpoint,
/// no auth required. used to resolve the trackId we feed to the private
/// storefront endpoints later (purchase, list versions, download).
enum Lookup {
    enum Error: Swift.Error, Equatable {
        case notFound
        case unexpectedShape(String)
        case http(status: Int)
    }

    static func byBundleID(
        _ bundleID: String,
        country: String,
        client: HTTPClient
    ) async throws -> App {
        let url = Endpoints.lookup(bundleID: bundleID, country: country)
        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.get.rawValue
        request.setValue(Endpoints.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await client.send(request)
        guard response.statusCode == 200 else {
            throw Error.http(status: response.statusCode)
        }
        let decoded = try JSONDecoder().decode(LookupResponse.self, from: data)
        guard let raw = decoded.results.first else {
            throw Error.notFound
        }
        return raw.toApp(country: country)
    }
}

private struct LookupResponse: Decodable {
    let resultCount: Int
    let results: [SoftwareItem]
}
