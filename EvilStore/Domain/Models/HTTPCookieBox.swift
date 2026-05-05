// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import Foundation

/// HTTPCookie is not Codable; this is the persisted shape we round-trip through Keychain.
struct HTTPCookieBox: Equatable, Codable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let expiresDate: Date?
    let isSecure: Bool
    let isHTTPOnly: Bool
}

extension HTTPCookieBox {
    init(_ cookie: HTTPCookie) {
        name = cookie.name
        value = cookie.value
        domain = cookie.domain
        path = cookie.path
        expiresDate = cookie.expiresDate
        isSecure = cookie.isSecure
        isHTTPOnly = cookie.isHTTPOnly
    }

    func toHTTPCookie() -> HTTPCookie? {
        var props: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path
        ]
        if let expiresDate { props[.expires] = expiresDate }
        if isSecure { props[.secure] = "TRUE" }
        return HTTPCookie(properties: props)
    }
}
