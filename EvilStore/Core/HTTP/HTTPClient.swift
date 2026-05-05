// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import Foundation

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
}

protocol HTTPClient {
    /// throttled URLSession.data wrapper. each request goes through the same
    /// AsyncThrottle gate so bursts don't trip Apple's rate limiter.
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

actor URLSessionHTTPClient: HTTPClient {
    private let session: URLSession
    private let throttle: AsyncThrottle

    init(session: URLSession = .shared, minInterval: TimeInterval = 0.5) {
        self.session = session
        throttle = AsyncThrottle(minInterval: minInterval)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        await throttle.wait()
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}
