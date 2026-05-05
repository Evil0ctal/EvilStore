// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import Foundation

struct Account: Equatable, Codable {
    enum Source: String, Codable { case systemBorrowed, manual }

    var source: Source
    var email: String
    var firstName: String
    var lastName: String
    /// numeric DSID assigned by Apple to this Apple ID
    var directoryServicesIdentifier: String
    /// short-lived token; absent if borrowed via filesystem and the keybag wouldn't decrypt
    var passwordToken: String?
    /// storefront short id like "143441" (US); take leading numeric segment if Apple returns "143441-19,29"
    var storefront: String
    /// host pod prefix; non-nil after a redirect like p25-buy.itunes.apple.com
    var pod: String?
    /// 12 hex chars, uppercase. shared with system App Store when source == .systemBorrowed
    var guid: String
    var cookies: [HTTPCookieBox]
    /// only persisted for .manual; .systemBorrowed always nil
    var encryptedPassword: Data?
}

extension Account: CustomDebugStringConvertible {
    /// must redact every secret-bearing field — see 2-doc §7.4
    var debugDescription: String {
        let dsid = redactTail(directoryServicesIdentifier, keep: 4)
        let guidRed = redactTail(guid, keep: 4)
        let token = passwordToken.map { redactTail($0, keep: 4) } ?? "nil"
        return "Account(source=\(source.rawValue), email=\(email), storefront=\(storefront), "
            + "dsid=\(dsid), guid=\(guidRed), passwordToken=\(token), cookies=\(cookies.count))"
    }
}

private func redactTail(_ s: String, keep: Int) -> String {
    guard s.count > keep else { return String(repeating: "•", count: s.count) }
    let mask = String(repeating: "•", count: s.count - keep)
    return mask + s.suffix(keep)
}
