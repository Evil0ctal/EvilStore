// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import Foundation

/// fetches the array of historic version external identifiers for an app.
/// requires an authenticated Account (DSID, GUID, cookies; passwordToken
/// helps on some ios versions but cookies alone often work).
enum ListVersions {
    enum Error: Swift.Error, Equatable {
        case http(status: Int)
        case unexpectedShape(String)
        case tokenExpired
        case licenseRequired
        case failure(failureType: String, customerMessage: String?)
    }

    static func run(
        account: Account,
        app: App,
        client: HTTPClient
    ) async throws -> [String] {
        let url = Endpoints.privateStorefront(pod: account.pod, guid: account.guid)
        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.post.rawValue
        request.setValue("application/x-apple-plist", forHTTPHeaderField: "Content-Type")
        request.setValue(Endpoints.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(account.directoryServicesIdentifier, forHTTPHeaderField: "iCloud-DSID")
        request.setValue(account.directoryServicesIdentifier, forHTTPHeaderField: "X-Dsid")

        // attach storefront cookies borrowed from system
        let cookies = account.cookies.compactMap { $0.toHTTPCookie() }
        for (key, value) in HTTPCookie.requestHeaderFields(with: cookies) {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let payload: [String: Any] = [
            "creditDisplay": "",
            "guid": account.guid,
            "salableAdamId": app.id
        ]
        request.httpBody = try PlistCoder.encodeXML(payload)

        let (data, response) = try await client.send(request)
        guard response.statusCode == 200 else {
            throw Error.http(status: response.statusCode)
        }

        let dict = try PlistCoder.decode(data)
        try checkFailure(dict)

        guard let items = dict["songList"] as? [[String: Any]],
              let first = items.first
        else {
            throw Error.unexpectedShape("songList missing or empty")
        }
        guard let metadata = first["metadata"] as? [String: Any],
              let identifiers = metadata["softwareVersionExternalIdentifiers"] as? [Any]
        else {
            throw Error.unexpectedShape("softwareVersionExternalIdentifiers missing")
        }

        // Apple returns identifiers oldest -> newest; reverse so callers see latest first.
        return identifiers.map { "\($0)" }.reversed()
    }

    private static func checkFailure(_ dict: [String: Any]) throws {
        let failure = dict["failureType"] as? String ?? ""
        guard !failure.isEmpty else { return }
        let customerMessage = dict["customerMessage"] as? String
        switch failure {
        case "2034", "2042":
            throw Error.tokenExpired
        case "9610":
            throw Error.licenseRequired
        default:
            throw Error.failure(failureType: failure, customerMessage: customerMessage)
        }
    }
}
