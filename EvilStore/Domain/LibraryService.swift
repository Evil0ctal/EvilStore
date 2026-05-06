// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import Foundation

/// scans /var/mobile/Media/EvilStore/Downloads/ for finished .ipa files and
/// publishes them grouped by bundle id.
///
/// file names follow the FileLayout convention:
///   <bundle-id>_<trackId>[_<displayVersion>].ipa
@MainActor
final class LibraryService: ObservableObject {
    @Published private(set) var entries: [LibraryEntry] = []
    @Published private(set) var lastError: String?

    func refresh() {
        let fm = FileManager.default
        let dir = FileLayout.downloads
        guard fm.fileExists(atPath: dir.path) else {
            entries = []
            return
        }
        do {
            let urls = try fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            entries = urls
                .filter { $0.pathExtension.lowercased() == "ipa" }
                .compactMap(parse)
                .sorted { $0.modifiedAt > $1.modifiedAt }
            lastError = nil
        } catch {
            lastError = "\(error)"
            entries = []
        }
    }

    func delete(_ entry: LibraryEntry) {
        try? FileManager.default.removeItem(at: entry.fileURL)
        refresh()
    }

    /// group entries by bundle id, preserving the global newest-first sort
    /// inside each group.
    func grouped() -> [(bundleID: String, items: [LibraryEntry])] {
        var seen: [String: [LibraryEntry]] = [:]
        var order: [String] = []
        for entry in entries {
            if seen[entry.bundleID] == nil {
                order.append(entry.bundleID)
            }
            seen[entry.bundleID, default: []].append(entry)
        }
        return order.map { ($0, seen[$0] ?? []) }
    }

    // MARK: - parsing

    private func parse(_ url: URL) -> LibraryEntry? {
        let stem = url.deletingPathExtension().lastPathComponent
        let parts = stem.split(separator: "_", omittingEmptySubsequences: true)
        guard !parts.isEmpty else { return nil }

        let bundleID = String(parts[0])
        let trackID: Int64? = parts.count >= 2 ? Int64(parts[1]) : nil
        let displayVersion: String? = parts.count >= 3
            ? parts.dropFirst(2).joined(separator: "_")
            : nil

        let attrs = (try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]))
        let size = Int64(attrs?.fileSize ?? 0)
        let modified = attrs?.contentModificationDate ?? Date()

        return LibraryEntry(
            fileURL: url,
            bundleID: bundleID,
            trackID: trackID,
            displayVersion: displayVersion,
            fileSize: size,
            modifiedAt: modified
        )
    }
}
