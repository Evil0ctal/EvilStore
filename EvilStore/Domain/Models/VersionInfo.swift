// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import Foundation

/// one entry in an app's version history. external identifier comes from
/// listVersions; the human-readable display version + release date come
/// from the partial-zip Info.plist peek (lands in m2.5).
struct VersionInfo: Equatable, Codable, Identifiable {
    var id: String {
        externalIdentifier
    }

    /// softwareVersionExternalIdentifier, e.g. "831776527"
    let externalIdentifier: String
    /// CFBundleShortVersionString, populated by PartialZipReader when ready
    let displayVersion: String?
    let releaseDate: Date?
    /// when we last fetched; drives cache invalidation
    let resolvedAt: Date

    init(
        externalIdentifier: String,
        displayVersion: String? = nil,
        releaseDate: Date? = nil,
        resolvedAt: Date = Date()
    ) {
        self.externalIdentifier = externalIdentifier
        self.displayVersion = displayVersion
        self.releaseDate = releaseDate
        self.resolvedAt = resolvedAt
    }
}
