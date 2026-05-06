// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import Foundation

/// single source of truth for storefront URLs. when Apple changes a path or
/// host this is the only file that should need editing.
enum Endpoints {
    // public itunes apis (no auth required)
    static let iTunesHost = "itunes.apple.com"
    static let lookupPath = "/lookup"
    static let searchPath = "/search"

    // private storefront (auth required) — used by M2+
    static let bagURL = URL(string: "https://init.itunes.apple.com/bag.xml")!
    static let buyHost = "buy.itunes.apple.com"
    static let pathPurchase = "/WebObjects/MZFinance.woa/wa/buyProduct"
    static let pathDownload = "/WebObjects/MZFinance.woa/wa/volumeStoreDownloadProduct"

    static func storeHost(pod: String?) -> String {
        pod.map { "p\($0)-\(buyHost)" } ?? buyHost
    }

    /// verified via ApplePackage; bump here when Apple changes the protocol.
    static let userAgent =
        "Configurator/2.0 (Macintosh; OS X 11.0.0; 16G29) AppleWebKit/2603.3.8"

    static func lookup(bundleID: String, country: String) -> URL {
        var c = URLComponents()
        c.scheme = "https"
        c.host = iTunesHost
        c.path = lookupPath
        c.queryItems = [
            .init(name: "bundleId", value: bundleID),
            .init(name: "country", value: country),
            .init(name: "limit", value: "1")
        ]
        return c.url!
    }

    static func search(term: String, country: String, limit: Int) -> URL {
        var c = URLComponents()
        c.scheme = "https"
        c.host = iTunesHost
        c.path = searchPath
        c.queryItems = [
            .init(name: "term", value: term),
            .init(name: "country", value: country),
            .init(name: "entity", value: "software"),
            .init(name: "limit", value: String(limit))
        ]
        return c.url!
    }
}
