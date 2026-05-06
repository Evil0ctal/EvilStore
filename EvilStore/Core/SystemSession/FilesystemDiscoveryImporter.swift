// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import Foundation

/// diagnostic-only "importer" that always throws. its job is to scan a
/// known list of paths where ios *might* keep storeaccountd cookies +
/// accountInfo, and return the listing as the error detail so the user
/// can paste it into a stealth probe report. never contributes to the
/// real Account merge.
final class FilesystemDiscoveryImporter: SystemSessionImporter {
    let name = "discover"

    func isAvailable() async -> Bool {
        true
    }

    func snapshot() async throws -> Account {
        throw SystemSessionError.fileFormatChanged(path: scan())
    }

    private func scan() -> String {
        var lines: [String] = []

        // candidate cookie files, ordered by historical ios likelihood
        let cookieCandidates: [String] = [
            "/var/mobile/Library/Cookies/com.apple.itunesstored.binarycookies",
            "/var/mobile/Library/Cookies/Cookies.binarycookies",
            "/var/mobile/Library/Caches/com.apple.itunesstored/Cookies/Cookies.binarycookies",
            "/var/mobile/Library/Caches/com.apple.itunesstored/Cookies.binarycookies",
            "/var/mobile/Library/com.apple.itunesstored/Cookies/Cookies.binarycookies",
            "/var/mobile/Library/com.apple.itunesstored/Cookies.binarycookies",
            "/var/mobile/Library/com.apple.itunesstored/com.apple.itunesstored.binarycookies",
            "/var/mobile/Library/Cookies/com.apple.appstored.binarycookies",
            "/var/mobile/Library/Cookies/Cookies.appstored.binarycookies"
        ]
        lines.append("== cookie candidates ==")
        for p in cookieCandidates {
            lines.append(probe(p))
        }

        // candidate accountInfo files
        let accountCandidates: [String] = [
            "/var/mobile/Library/com.apple.itunesstored/accountInfo",
            "/var/mobile/Library/com.apple.itunesstored/accountInfo.plist",
            "/var/mobile/Library/com.apple.itunesstored/iTunesStoreAccount.plist",
            "/var/mobile/Library/com.apple.itunesstored/AppleAccountInfo.plist",
            "/var/mobile/Library/Preferences/com.apple.itunesstored.plist",
            "/var/mobile/Library/Preferences/com.apple.appstored.plist",
            "/var/mobile/Library/Application Support/com.apple.appstored/account.plist"
        ]
        lines.append("== accountInfo candidates ==")
        for p in accountCandidates {
            lines.append(probe(p))
        }

        // top-level listings of the directories most likely to contain auth state
        let dirsToList: [String] = [
            "/var/mobile/Library/Cookies",
            "/var/mobile/Library/com.apple.itunesstored",
            "/var/mobile/Library/Caches/com.apple.itunesstored",
            "/var/mobile/Library/Preferences",
            "/var/mobile/Containers/Data/InternalDaemon"
        ]
        lines.append("== directory listings ==")
        for d in dirsToList {
            lines.append(listDir(d))
        }

        // iOS 16+ moved daemon state into per-uuid containers; scan
        // /var/mobile/Containers/Data/InternalDaemon/ for the storeaccountd one.
        lines.append("== InternalDaemon containers (filtered for store/itunes) ==")
        lines.append(contentsOf: scanInternalDaemons())

        // /var/mobile/Library/Preferences for store-related plists
        lines.append("== Preferences/*store*.plist ==")
        lines.append(contentsOf: scanPreferences())

        return lines.joined(separator: "\n  ")
    }

    private func probe(_ path: String) -> String {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else {
            return "[-] \(path)"
        }
        let url = URL(fileURLWithPath: path)
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        return "[+] \(path) (\(size)B)"
    }

    private func listDir(_ path: String) -> String {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else {
            return "[-] \(path)/"
        }
        guard let names = try? fm.contentsOfDirectory(atPath: path) else {
            return "[!] \(path)/ unreadable"
        }
        let listing = names.sorted().joined(separator: ",")
        return "[+] \(path)/ → \(listing)"
    }

    private func scanInternalDaemons() -> [String] {
        let root = "/var/mobile/Containers/Data/InternalDaemon"
        let fm = FileManager.default
        guard let uuids = try? fm.contentsOfDirectory(atPath: root) else {
            return ["[-] \(root)/ unreadable"]
        }
        var out: [String] = []
        for uuid in uuids.sorted() {
            let metaPath = "\(root)/\(uuid)/.com.apple.mobile_container_manager.metadata.plist"
            guard fm.fileExists(atPath: metaPath),
                  let data = try? Data(contentsOf: URL(fileURLWithPath: metaPath)),
                  let plist = try? PropertyListSerialization
                  .propertyList(from: data, options: [], format: nil) as? [String: Any],
                  let id = plist["MCMMetadataIdentifier"] as? String
            else { continue }
            let lower = id.lowercased()
            guard lower.contains("itunes") || lower.contains("appstore") || lower.contains("store") else { continue }
            // list this container's Library/Cookies/ and root contents
            let lib = "\(root)/\(uuid)/Library"
            let cookies = "\(lib)/Cookies"
            let libNames = (try? fm.contentsOfDirectory(atPath: lib))?.sorted().joined(separator: ",") ?? "(missing)"
            let cookieNames = (try? fm.contentsOfDirectory(
                atPath: cookies
            ))?.sorted().joined(separator: ",") ?? "(missing)"
            out.append("[+] \(id) @ \(uuid)")
            out.append("    Library/: \(libNames)")
            out.append("    Library/Cookies/: \(cookieNames)")
        }
        return out
    }

    private func scanPreferences() -> [String] {
        let root = "/var/mobile/Library/Preferences"
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: root) else {
            return ["[-] \(root)/ unreadable"]
        }
        let matched = names
            .filter {
                $0.lowercased().contains("itunes") || $0.lowercased().contains("appstore") || $0.lowercased()
                    .contains("store")
            }
            .sorted()
        if matched.isEmpty { return ["(no store-related plists)"] }
        return matched.map { "[+] \($0)" }
    }
}
