// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import Foundation

/// Reads the storeaccountd state straight off /var/mobile/Library/com.apple.itunesstored/.
/// Requires the no-sandbox + abs-path-read entitlements (M0 baseline already grants them).
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
        let info = try readAccountInfo()
        let cookies = readCookies()
        let token = try? readPasswordToken()
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

    /// keys observed across iOS 14-17 (ApplePackage + ipatool + community dumps):
    ///   email      : "AppleID" / "appleId" / "DSPersonID-Email"
    ///   first/last : "FirstName" / "LastName" or via "AccountName"
    ///   dsid       : "DSPersonID" / "DSID"
    ///   storefront : "Storefront" / "StoreFront" / "X-Apple-Store-Front"
    ///   guid       : "GUID" / "DeviceID"
    /// We try each candidate in turn. M0.5 PoC will narrow this once we have real samples.
    private func readAccountInfo() throws -> AccountInfoFile {
        let candidates = [
            storeRoot.appendingPathComponent("accountInfo"),
            storeRoot.appendingPathComponent("accountInfo.plist"),
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
        if let lastError {
            throw lastError
        }
        throw SystemSessionError.fileFormatChanged(path: storeRoot.appendingPathComponent("accountInfo").path)
    }

    private func parseAccountInfo(at url: URL) throws -> AccountInfoFile {
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let dict = plist as? [String: Any] else {
            throw SystemSessionError.fileFormatChanged(path: url.path)
        }
        let email = firstString(dict, keys: ["AppleID", "appleId", "DSPersonID-Email", "Email"])
        let dsid = firstString(dict, keys: ["DSPersonID", "DSID", "dsid"])
        let storefront = firstString(dict, keys: ["Storefront", "StoreFront", "X-Apple-Store-Front"])
        let guidRaw = firstString(dict, keys: ["GUID", "DeviceID"])
        let firstName = firstString(dict, keys: ["FirstName", "firstName"])
        let lastName = firstString(dict, keys: ["LastName", "lastName"])

        guard let dsid, let storefront, let guidRaw else {
            throw SystemSessionError.fileFormatChanged(path: url.path)
        }
        return AccountInfoFile(
            email: email ?? "",
            firstName: firstName ?? "",
            lastName: lastName ?? "",
            dsid: dsid,
            storefront: storefrontHead(storefront),
            guid: normalizeGuid(guidRaw)
        )
    }

    /// "143441-19,29" -> "143441"
    private func storefrontHead(_ raw: String) -> String {
        raw.split(separator: "-").first.map(String.init) ?? raw
    }

    /// uppercase + strip ":" so the value matches what storefront API expects in Authenticate.swift
    private func normalizeGuid(_ raw: String) -> String {
        raw.replacingOccurrences(of: ":", with: "").uppercased()
    }

    // MARK: - tokens

    /// best-effort: accountTokens may be present, encrypted, or absent depending on iOS keybag.
    /// throw on missing/malformed; caller should treat the failure as non-fatal.
    private func readPasswordToken() throws -> String {
        let url = storeRoot.appendingPathComponent("accountTokens")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SystemSessionError.fileFormatChanged(path: url.path)
        }
        let data = try Data(contentsOf: url)
        // tokens file is sometimes a plist dict, sometimes raw encrypted blob.
        // best-effort plist read first.
        if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
           let token = firstString(plist, keys: ["passwordToken", "PasswordToken", "Token"]) {
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

    private func firstString(_ dict: [String: Any], keys: [String]) -> String? {
        for k in keys {
            if let s = dict[k] as? String, !s.isEmpty {
                return s
            }
            if let n = dict[k] as? NSNumber {
                return n.stringValue
            }
        }
        return nil
    }
}

private struct AccountInfoFile {
    var email: String
    var firstName: String
    var lastName: String
    var dsid: String
    var storefront: String
    var guid: String
}
