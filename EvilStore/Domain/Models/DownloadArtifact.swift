// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import Foundation

/// what AppStoreClient.download produces: the apple-signed .ipa URL we are
/// supposed to GET, plus the sinf tickets and iTunesMetadata payload that we
/// inject into that .ipa before handing it off to TrollStore.
struct DownloadArtifact: Equatable {
    let ipaURL: URL
    let md5: String?
    let sinfs: [Sinf]
    /// raw plist body to drop into the resulting ipa as iTunesMetadata.plist
    let iTunesMetadata: Data
    let displayVersion: String?
    let releaseDate: Date?
}
