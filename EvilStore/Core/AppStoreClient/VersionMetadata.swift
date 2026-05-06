// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import Foundation

/// resolves the human-readable version string + release date for a single
/// historic external identifier. uses the same `volumeStoreDownloadProduct`
/// endpoint as `download`, but only reads the response metadata — Apple's
/// signed `.ipa` URL is discarded here. m3 reuses the same call when it
/// actually downloads the ipa bytes.
enum VersionMetadata {
    enum Error: Swift.Error {
        case http(status: Int)
        case unexpectedShape(String)
        case tokenExpired
        case licenseRequired
        case failure(failureType: String, customerMessage: String?)
    }

    struct Resolved {
        let externalIdentifier: String
        let displayVersion: String?
        let releaseDate: Date?
    }

    static func run(
        externalIdentifier: String,
        account: Account,
        app: App,
        client: HTTPClient
    ) async throws -> Resolved {
        let url = Endpoints.privateStorefront(pod: account.pod, guid: account.guid)
        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.post.rawValue
        request.setValue("application/x-apple-plist", forHTTPHeaderField: "Content-Type")
        request.setValue(Endpoints.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(account.directoryServicesIdentifier, forHTTPHeaderField: "iCloud-DSID")
        request.setValue(account.directoryServicesIdentifier, forHTTPHeaderField: "X-Dsid")

        let cookies = account.cookies.compactMap { $0.toHTTPCookie() }
        for (key, value) in HTTPCookie.requestHeaderFields(with: cookies) {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let payload: [String: Any] = [
            "creditDisplay": "",
            "guid": account.guid,
            "salableAdamId": app.id,
            "externalVersionId": externalIdentifier
        ]
        request.httpBody = try PlistCoder.encodeXML(payload)

        let (data, response) = try await client.send(request)
        guard response.statusCode == 200 else {
            throw Error.http(status: response.statusCode)
        }
        let dict = try PlistCoder.decode(data)
        try checkFailure(dict)

        guard let items = dict["songList"] as? [[String: Any]],
              let first = items.first,
              let metadata = first["metadata"] as? [String: Any]
        else {
            throw Error.unexpectedShape("songList[0].metadata missing")
        }

        return Resolved(
            externalIdentifier: externalIdentifier,
            displayVersion: readDisplayVersion(metadata),
            releaseDate: readReleaseDate(metadata)
        )
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

    private static func readDisplayVersion(_ metadata: [String: Any]) -> String? {
        for key in ["bundleShortVersionString", "CFBundleShortVersionString"] {
            if let value = metadata[key] as? String, !value.isEmpty {
                return value
            }
            if let value = metadata[key] as? NSNumber {
                return value.stringValue
            }
        }
        return nil
    }

    private static func readReleaseDate(_ metadata: [String: Any]) -> Date? {
        for key in ["releaseDate", "ReleaseDate"] {
            guard let raw = metadata[key] else { continue }
            if let date = raw as? Date { return date }
            if let str = raw as? String, let date = parseISO8601(str) { return date }
            if let n = raw as? NSNumber {
                return Date(timeIntervalSince1970: n.doubleValue)
            }
        }
        return nil
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
