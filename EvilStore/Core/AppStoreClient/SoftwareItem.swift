// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import Foundation

/// raw shape of a /lookup or /search hit. private to AppStoreClient — the
/// public surface is `App` with sanitized field names.
struct SoftwareItem: Decodable {
    let trackId: Int64
    let bundleId: String
    let trackName: String
    let artistName: String?
    let version: String?
    let primaryGenreName: String?
    let formattedPrice: String?
    let artworkUrl512: String?
    let artworkUrl100: String?
    let artworkUrl60: String?

    func toApp(country: String) -> App {
        App(
            id: trackId,
            bundleID: bundleId,
            name: trackName,
            artistName: artistName ?? "",
            version: version ?? "",
            storefront: country,
            artworkURL: bestArtworkURL(),
            primaryGenre: primaryGenreName,
            formattedPrice: formattedPrice ?? "Free"
        )
    }

    private func bestArtworkURL() -> URL? {
        for raw in [artworkUrl512, artworkUrl100, artworkUrl60] {
            if let raw, let url = URL(string: raw) { return url }
        }
        return nil
    }
}
