// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import Foundation

/// one .ipa sitting in /var/mobile/Media/EvilStore/Downloads/. parsed from
/// the file name we wrote at download time (FileLayout.ipaName), so no need
/// to re-open the archive every time the Library tab refreshes.
struct LibraryEntry: Identifiable, Equatable {
    /// stable id derived from the path
    var id: String {
        fileURL.path
    }

    let fileURL: URL
    let bundleID: String
    let trackID: Int64?
    let displayVersion: String?
    let fileSize: Int64
    let modifiedAt: Date
}
