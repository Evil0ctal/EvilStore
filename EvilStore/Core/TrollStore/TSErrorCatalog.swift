// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import Foundation

/// human-readable mapping for TrollStore's installer error codes. TrollStore
/// reports these in its own UI (we don't get a callback over the URL scheme)
/// but Library + Downloads rows include a help text so users searching the
/// codes online land somewhere with context.
enum TSErrorCatalog {
    struct Entry {
        let code: Int
        let summary: String
        let action: String
    }

    static let entries: [Entry] = [
        .init(
            code: 166,
            summary: "ipa file unreadable",
            action: "re-download"
        ),
        .init(
            code: 167,
            summary: "ipa missing an app bundle",
            action: "re-download or pick another version"
        ),
        .init(
            code: 168,
            summary: "could not extract the ipa",
            action: "re-download"
        ),
        .init(
            code: 171,
            summary: "another app uses this bundle id",
            action: "TrollStore offers force-install — usually safe"
        ),
        .init(
            code: 173,
            summary: "ldid is missing on the device",
            action: "install ldid via TrollStore Settings"
        ),
        .init(
            code: 175,
            summary: "could not sign the binary",
            action: "report at github.com/Evil0ctal/EvilStore/issues"
        ),
        .init(
            code: 179,
            summary: "system app has the same bundle id",
            action: "skip — installing risks a bootloop"
        ),
        .init(
            code: 180,
            summary: "main binary is encrypted",
            action: "this ipa came from a non-decrypted source; pick another"
        ),
        .init(
            code: 182,
            summary: "developer mode required",
            action: "reboot, enable developer mode, retry"
        ),
        .init(
            code: 184,
            summary: "some plug-ins still encrypted",
            action: "main app probably works; plug-ins may not"
        ),
        .init(
            code: 185,
            summary: "CoreTrust bypass returned non-zero",
            action: "report at github.com/Evil0ctal/EvilStore/issues"
        )
    ]

    static func lookup(_ code: Int) -> Entry? {
        entries.first { $0.code == code }
    }
}
