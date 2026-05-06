// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import Foundation

/// reads the storeaccountd state straight off
/// /var/mobile/Library/com.apple.itunesstored/. requires the no-sandbox +
/// abs-path-read entitlements (M0 baseline already grants them).
final class FileSystemImporter: SystemSessionImporter {
    let name = "filesystem"

    private let storeRoot: URL
    private let cookiesPath: URL

    init(
        storeRoot: URL = URL(fileURLWithPath: "/var/mobile/Library/com.apple.itunesstored"),
        cookiesPath: URL = URL(fileURLWithPath: "/var/mobile/Library/Cookies/com.apple.itunesstored.binarycookies")
    ) {
        self.storeRoot = storeRoot
        self.cookiesPath = cookiesPath
    }

    func isAvailable() async -> Bool {
        FileManager.default.fileExists(atPath: storeRoot.path)
    }

    func snapshot() async throws -> Account {
        guard FileManager.default.fileExists(atPath: storeRoot.path) else {
            throw SystemSessionError.notLoggedIn
        }
        let cookies = readCookies()
        let token = try? readPasswordToken()
        // accountInfo may not exist on this ios; that's not fatal — we still
        // contribute cookies and a possible token. CompositeImporter merges.
        let info = (try? readAccountInfo()) ?? AccountInfoFile.empty
        return Account(
            source: .systemBorrowed,
            email: info.email,
            firstName: info.firstName,
            lastName: info.lastName,
            directoryServicesIdentifier: info.dsid,
            passwordToken: token,
            storefront: info.storefront,
            pod: nil,
            guid: info.guid,
            cookies: cookies.map(HTTPCookieBox.init),
            encryptedPassword: nil
        )
    }

    // MARK: - accountInfo

    /// candidate field names per role. apple has reshuffled these across
    /// ios majors and even between point releases, so we deep-walk the plist
    /// (not just the top level) and try every key.
    private static let dsidKeys = [
        "DSPersonID", "DSID", "dsid", "DsPersonId", "ds-person-id",
        "AppleID", "appleAccountInfoDSID"
    ]
    private static let storefrontKeys = [
        "Storefront", "StoreFront", "storefront", "X-Apple-Store-Front",
        "storeFrontIdentifier", "storefrontIdentifier"
    ]
    private static let guidKeys = [
        "GUID", "guid", "DeviceGUID", "deviceGUID", "DeviceID"
    ]
    private static let emailKeys = [
        "AppleID", "appleId", "DSPersonID-Email", "Email", "username",
        "AppleAccountEmail", "iTunesAccount"
    ]
    private static let firstNameKeys = ["FirstName", "firstName"]
    private static let lastNameKeys = ["LastName", "lastName"]

    private func readAccountInfo() throws -> AccountInfoFile {
        let candidates = [
            storeRoot.appendingPathComponent("accountInfo"),
            storeRoot.appendingPathComponent("accountInfo.plist")
        ]
        var lastError: Error?
        for url in candidates {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                return try parseAccountInfo(at: url)
            } catch {
                lastError = error
            }
        }
        if let lastError { throw lastError }
        throw SystemSessionError.fileFormatChanged(path: storeRoot.appendingPathComponent("accountInfo").path)
    }

    /// returns whatever fields the plist contains; missing fields are empty.
    /// only the dsid requirement is upheld — without it this file is useless
    /// to us and we throw with a shape dump.
    private func parseAccountInfo(at url: URL) throws -> AccountInfoFile {
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let dict = plist as? [String: Any] else {
            throw SystemSessionError.fileFormatChanged(path: "\(url.path) [root not a dict]")
        }

        let dsid = recursiveString(dict, keys: Self.dsidKeys)
        let storefrontRaw = recursiveString(dict, keys: Self.storefrontKeys)
        let guidRaw = recursiveString(dict, keys: Self.guidKeys)
        let email = recursiveString(dict, keys: Self.emailKeys)
        let firstName = recursiveString(dict, keys: Self.firstNameKeys)
        let lastName = recursiveString(dict, keys: Self.lastNameKeys)

        guard let dsid else {
            // accountInfo with no dsid is unusable — give the shape so we can
            // patch the candidate keys next iteration.
            let summary = describeStructure(dict)
            throw SystemSessionError.fileFormatChanged(
                path: "\(url.path) [missing=dsid shape=\(summary)]"
            )
        }

        return AccountInfoFile(
            email: email ?? "",
            firstName: firstName ?? "",
            lastName: lastName ?? "",
            dsid: dsid,
            storefront: storefrontRaw.map(storefrontHead) ?? "",
            guid: guidRaw.map(normalizeGuid) ?? ""
        )
    }

    /// "143441-19,29" -> "143441"
    private func storefrontHead(_ raw: String) -> String {
        raw.split(separator: "-").first.map(String.init) ?? raw
    }

    /// uppercase + strip ":" so the value matches what storefront API expects
    private func normalizeGuid(_ raw: String) -> String {
        raw.replacingOccurrences(of: ":", with: "").uppercased()
    }

    // MARK: - tokens

    private func readPasswordToken() throws -> String {
        let url = storeRoot.appendingPathComponent("accountTokens")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SystemSessionError.fileFormatChanged(path: url.path)
        }
        let data = try Data(contentsOf: url)
        if let plist = try? PropertyListSerialization
            .propertyList(from: data, options: [], format: nil) as? [String: Any],
            let token = recursiveString(plist, keys: ["passwordToken", "PasswordToken", "Token"])
        {
            return token
        }
        throw SystemSessionError.tokenDecryptionFailed
    }

    // MARK: - cookies

    private func readCookies() -> [HTTPCookie] {
        guard FileManager.default.fileExists(atPath: cookiesPath.path) else { return [] }
        return (try? BinaryCookiesParser.parse(at: cookiesPath)) ?? []
    }

    // MARK: - helpers

    /// walk dicts/arrays depth-first looking for any of `keys` (case-insensitive).
    /// returns the first non-empty string/number-stringified match found.
    private func recursiveString(_ value: Any, keys: [String]) -> String? {
        let lowered = Set(keys.map { $0.lowercased() })

        if let dict = value as? [String: Any] {
            for (k, v) in dict {
                guard lowered.contains(k.lowercased()) else { continue }
                if let s = v as? String, !s.isEmpty { return s }
                if let n = v as? NSNumber { return n.stringValue }
            }
            for v in dict.values {
                if let found = recursiveString(v, keys: keys) { return found }
            }
        }
        if let array = value as? [Any] {
            for child in array {
                if let found = recursiveString(child, keys: keys) { return found }
            }
        }
        return nil
    }

    /// summarises a plist structure as "{key1:str, key2:dict{...}, key3:array[N]}"
    /// — values are not included so the dump is safe to ship in a diagnostic.
    private func describeStructure(_ value: Any, depth: Int = 0) -> String {
        if depth > 3 { return "..." }
        if let dict = value as? [String: Any] {
            let parts = dict.keys.sorted().map { k -> String in
                let v = dict[k] as Any
                return "\(k):\(typeTag(v, depth: depth + 1))"
            }
            return "{\(parts.joined(separator: ","))}"
        }
        if let array = value as? [Any] {
            return "[\(array.count)]"
        }
        return typeTag(value, depth: depth)
    }

    private func typeTag(_ value: Any, depth: Int) -> String {
        switch value {
        case is String: return "str"
        case is NSNumber: return "num"
        case is Date: return "date"
        case is Data: return "data"
        case let d as [String: Any]: return describeStructure(d, depth: depth)
        case let a as [Any]: return "[\(a.count)]"
        default: return "?"
        }
    }
}

private struct AccountInfoFile {
    var email: String
    var firstName: String
    var lastName: String
    var dsid: String
    var storefront: String
    var guid: String

    static let empty = AccountInfoFile(
        email: "", firstName: "", lastName: "", dsid: "", storefront: "", guid: ""
    )
}
