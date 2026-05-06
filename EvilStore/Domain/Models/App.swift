// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import Foundation

struct App: Equatable, Codable, Identifiable {
    let id: Int64 // salableAdamId / Apple's trackId
    let bundleID: String
    let name: String
    let artistName: String
    let version: String // current marketing version on the store
    let storefront: String // country code as fed to lookup, e.g. "US"
    let artworkURL: URL?
    let primaryGenre: String?
    let formattedPrice: String // "Free" / "$1.99"
}
