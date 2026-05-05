// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import Foundation

/// curated list of itunes storefront country codes for the country menu.
/// the full list (~150) is not exposed here on purpose — mostly used
/// regions only. when M2 lands the matching numeric storefront id ("143441")
/// gets added here too.
enum CountryCatalog {
    struct Country: Equatable, Hashable {
        let code: String // ISO alpha-2
        let name: String
    }

    static let popular: [Country] = [
        .init(code: "US", name: "United States"),
        .init(code: "CN", name: "China"),
        .init(code: "JP", name: "Japan"),
        .init(code: "GB", name: "United Kingdom"),
        .init(code: "DE", name: "Germany"),
        .init(code: "FR", name: "France"),
        .init(code: "KR", name: "South Korea"),
        .init(code: "TW", name: "Taiwan"),
        .init(code: "HK", name: "Hong Kong"),
        .init(code: "SG", name: "Singapore"),
        .init(code: "AU", name: "Australia"),
        .init(code: "CA", name: "Canada")
    ]
}
