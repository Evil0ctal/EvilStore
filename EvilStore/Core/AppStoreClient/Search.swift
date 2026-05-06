// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import Foundation

/// search apps via itunes.apple.com/search. public endpoint, no auth.
enum Search {
    enum Error: Swift.Error, Equatable {
        case http(status: Int)
        case unexpectedShape(String)
    }

    static func apps(
        term: String,
        country: String,
        limit: Int = 25,
        client: HTTPClient
    ) async throws -> [App] {
        let url = Endpoints.search(term: term, country: country, limit: limit)
        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.get.rawValue
        request.setValue(Endpoints.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await client.send(request)
        guard response.statusCode == 200 else {
            throw Error.http(status: response.statusCode)
        }
        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        return decoded.results.map { $0.toApp(country: country) }
    }
}

private struct SearchResponse: Decodable {
    let resultCount: Int
    let results: [SoftwareItem]
}
