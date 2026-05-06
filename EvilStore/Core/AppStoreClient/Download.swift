// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import Foundation

/// asks the storefront for a signed ipa URL + sinf tickets + the metadata
/// blob. callers (DownloadEngine) GET the URL to fetch bytes, then hand the
/// ipa + this artifact to IPAPatcher for in-place injection.
enum Download {
    enum Error: Swift.Error {
        case http(status: Int)
        case unexpectedShape(String)
        case tokenExpired
        case licenseRequired
        case failure(failureType: String, customerMessage: String?)
        case metadataEncoding
    }

    static func run(
        externalIdentifier: String?,
        account: Account,
        app: App,
        client: HTTPClient
    ) async throws -> DownloadArtifact {
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

        var payload: [String: Any] = [
            "creditDisplay": "",
            "guid": account.guid,
            "salableAdamId": app.id
        ]
        if let externalIdentifier {
            payload["externalVersionId"] = externalIdentifier
        }
        request.httpBody = try PlistCoder.encodeXML(payload)

        let (data, response) = try await client.send(request)
        guard response.statusCode == 200 else {
            throw Error.http(status: response.statusCode)
        }

        let dict = try PlistCoder.decode(data)
        try checkFailure(dict)

        guard let items = dict["songList"] as? [[String: Any]],
              let item = items.first
        else {
            throw Error.unexpectedShape("songList missing")
        }
        guard let urlString = item["URL"] as? String,
              let ipaURL = URL(string: urlString)
        else {
            throw Error.unexpectedShape("URL missing")
        }
        guard var metadata = item["metadata"] as? [String: Any] else {
            throw Error.unexpectedShape("metadata missing")
        }

        // ipatool/ApplePackage append apple-id + userName so installd
        // recognises the signed copy. mirror that.
        metadata["apple-id"] = account.email
        metadata["userName"] = account.email

        let metadataBlob = try PlistCoder.encodeXML(metadata)

        let sinfs = parseSinfs(item["sinfs"])
        let displayVersion = readDisplayVersion(metadata)
        let releaseDate = readReleaseDate(metadata)

        return DownloadArtifact(
            ipaURL: ipaURL,
            md5: item["md5"] as? String,
            sinfs: sinfs,
            iTunesMetadata: metadataBlob,
            displayVersion: displayVersion,
            releaseDate: releaseDate
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

    private static func parseSinfs(_ raw: Any?) -> [Sinf] {
        guard let array = raw as? [[String: Any]] else { return [] }
        return array.compactMap { dict in
            guard let id = dict["id"] as? Int64 ?? (dict["id"] as? NSNumber)?.int64Value,
                  let data = dict["sinf"] as? Data
            else {
                return nil
            }
            return Sinf(id: id, data: data)
        }
    }

    private static func readDisplayVersion(_ metadata: [String: Any]) -> String? {
        for key in ["bundleShortVersionString", "CFBundleShortVersionString"] {
            if let s = metadata[key] as? String, !s.isEmpty { return s }
        }
        return nil
    }

    private static func readReleaseDate(_ metadata: [String: Any]) -> Date? {
        if let date = metadata["releaseDate"] as? Date { return date }
        if let str = metadata["releaseDate"] as? String {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = f.date(from: str) { return date }
            f.formatOptions = [.withInternetDateTime]
            return f.date(from: str)
        }
        return nil
    }
}
