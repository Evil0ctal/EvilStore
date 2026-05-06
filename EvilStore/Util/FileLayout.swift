// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import Foundation

/// canonical paths shared by Domain + UI. tipa-installed apps live in a
/// sandbox container by default but the no-sandbox entitlement lets us
/// place persistent artifacts under /var/mobile/Media so the Files app
/// (and the user) can find them.
enum FileLayout {
    static let root = URL(fileURLWithPath: "/var/mobile/Media/EvilStore")
    static var downloads: URL {
        root.appendingPathComponent("Downloads")
    }

    static var cache: URL {
        root.appendingPathComponent("Cache")
    }

    static var logs: URL {
        root.appendingPathComponent("Logs")
    }

    /// best effort. non-fatal if the directories already exist or can't be
    /// created (e.g. running on a non-trollstore device for diagnostics).
    static func ensureDirs() {
        let fm = FileManager.default
        for dir in [downloads, cache, logs] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    static func ipaName(app: App, displayVersion: String?) -> String {
        var parts: [String] = []
        if !app.bundleID.isEmpty { parts.append(app.bundleID) }
        parts.append(String(app.id))
        if let v = displayVersion, !v.isEmpty {
            parts.append(v)
        }
        return parts.joined(separator: "_") + ".ipa"
    }

    static func downloadDestination(app: App, displayVersion: String?) -> URL {
        downloads.appendingPathComponent(ipaName(app: app, displayVersion: displayVersion))
    }
}
