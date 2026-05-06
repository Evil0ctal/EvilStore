// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import Foundation

/// path F — read /var/mobile/Library/Preferences/com.apple.itunescloud.plist.
///
/// on ios 15.x this plist is the only on-disk source we've found that
/// holds the full cookie set apple uses for storefront calls (the
/// itunesstored daemon migrated its cookies into AMS-managed defaults
/// but the iTunesCloud daemon kept the latest cookie header it received).
///
/// the relevant key is
///   ICDefaultsKeyLastCookieHeadersForRevokingMusicUserTokens
/// which is a dict with one entry — { "Cookie": "<header value>" }.
/// despite the "music" naming, the cookies are storefront-wide because
/// itunes.apple.com / buy.itunes.apple.com share the same session.
final class ITunesCloudImporter: SystemSessionImporter {
    let name = "itunescloud"

    private let plistPath: String

    init(plistPath: String = "/var/mobile/Library/Preferences/com.apple.itunescloud.plist") {
        self.plistPath = plistPath
    }

    func isAvailable() async -> Bool {
        FileManager.default.fileExists(atPath: plistPath)
    }

    func snapshot() async throws -> Account {
        guard FileManager.default.fileExists(atPath: plistPath) else {
            throw SystemSessionError.notLoggedIn
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: plistPath))
        guard let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            as? [String: Any]
        else {
            throw SystemSessionError.fileFormatChanged(path: "\(plistPath) [root not a dict]")
        }

        let dsid = readDSID(plist)
        let storefront = readStorefront(plist)
        let cookieHeader = readCookieHeader(plist)
        let cookies = cookieHeader.flatMap { Self.parseCookieHeader($0, defaultDomain: ".apple.com") } ?? []

        return Account(
            source: .systemBorrowed,
            email: "",
            firstName: "",
            lastName: "",
            directoryServicesIdentifier: dsid ?? "",
            passwordToken: nil,
            storefront: storefrontHead(storefront ?? ""),
            pod: nil,
            guid: "",
            cookies: cookies.map(HTTPCookieBox.init),
            encryptedPassword: nil
        )
    }

    // MARK: - readers

    private func readDSID(_ plist: [String: Any]) -> String? {
        if let v = plist["ICDefaultsKeyLastActiveAccountDSID"] {
            if let s = v as? String, !s.isEmpty { return s }
            if let n = v as? NSNumber { return n.stringValue }
        }
        // fallback: subscription status cache key.lastKnownActiveDSID
        if let cache = plist["ICDefaultsCachedSubscriptionStatus"] as? [String: Any],
           let n = cache["lastKnownActiveDSID"] as? NSNumber
        {
            return n.stringValue
        }
        return nil
    }

    private func readStorefront(_ plist: [String: Any]) -> String? {
        if let cache = plist["ICDefaultsKeyLastKnownSubscriptionStatusBaseCacheKey"] as? [String: Any],
           let s = cache["storefrontID"] as? String, !s.isEmpty
        {
            return s
        }
        return nil
    }

    private func readCookieHeader(_ plist: [String: Any]) -> String? {
        let key = "ICDefaultsKeyLastCookieHeadersForRevokingMusicUserTokens"
        guard let dict = plist[key] as? [String: Any],
              let header = dict["Cookie"] as? String,
              !header.isEmpty
        else {
            return nil
        }
        return header
    }

    // MARK: - parser

    /// parses an HTTP `Cookie:` request header value into individual cookies.
    /// format is `name1=value1; name2=value2; ...`. each cookie is bound to
    /// the supplied `defaultDomain` and root path so URLSession will attach
    /// it to any apple.com subdomain.
    static func parseCookieHeader(_ header: String, defaultDomain: String) -> [HTTPCookie] {
        var trimmed = header.trimmingCharacters(in: .whitespaces)
        if trimmed.lowercased().hasPrefix("cookie:") {
            trimmed = String(trimmed.dropFirst("cookie:".count)).trimmingCharacters(in: .whitespaces)
        }
        let pairs = trimmed.components(separatedBy: ";")
        var out: [HTTPCookie] = []
        for raw in pairs {
            let pair = raw.trimmingCharacters(in: .whitespaces)
            guard !pair.isEmpty,
                  let eq = pair.firstIndex(of: "="),
                  eq != pair.startIndex
            else {
                continue
            }
            let name = String(pair[..<eq])
            let value = String(pair[pair.index(after: eq)...])
            let props: [HTTPCookiePropertyKey: Any] = [
                .name: name,
                .value: value,
                .domain: defaultDomain,
                .path: "/"
            ]
            if let cookie = HTTPCookie(properties: props) {
                out.append(cookie)
            }
        }
        return out
    }

    private func storefrontHead(_ raw: String) -> String {
        raw.split(separator: "-").first.map(String.init) ?? raw
    }
}
