// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import Foundation
import SQLite3

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

        // m5e: probe ios 15-era sqlite databases that storeaccountd uses
        lines.append("== sqlite probe ==")
        let dbCandidates = [
            "/var/mobile/Library/com.apple.itunesstored/itunesstored2.sqlitedb",
            "/var/mobile/Library/com.apple.itunesstored/itunesstored_private.sqlitedb",
            "/var/mobile/Library/com.apple.itunesstored/kvs.sqlitedb"
        ]
        for dbPath in dbCandidates {
            lines.append(contentsOf: probeSqlite(dbPath))
        }

        // m5e: dump the two plist preferences that exist on this device
        lines.append("== plist dumps (values redacted if long) ==")
        let plistDumps = [
            "/var/mobile/Library/Preferences/com.apple.itunesstored.plist",
            "/var/mobile/Library/Preferences/com.apple.appstored.plist"
        ]
        for plistPath in plistDumps {
            lines.append(contentsOf: dumpPlist(plistPath))
        }

        return lines.joined(separator: "\n  ")
    }

    // MARK: - sqlite

    private func probeSqlite(_ path: String) -> [String] {
        guard FileManager.default.fileExists(atPath: path) else {
            return ["[-] \(path)"]
        }
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK else {
            let msg = sqlite3_errmsg(db).map { String(cString: $0) } ?? "?"
            sqlite3_close(db)
            return ["[!] \(path) open failed: \(msg)"]
        }
        defer { sqlite3_close(db) }

        var out = ["[+] \(path)"]
        let tables = listTables(db: db!)
        for t in tables {
            let cols = listColumns(db: db!, table: t)
            let rowCount = countRows(db: db!, table: t)
            out.append("    table \(t) [\(rowCount) rows]")
            for col in cols {
                out.append("      • \(col)")
            }
        }
        return out
    }

    private func listTables(db: OpaquePointer) -> [String] {
        var stmt: OpaquePointer?
        let q = "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
        guard sqlite3_prepare_v2(db, q, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var out: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let cstr = sqlite3_column_text(stmt, 0) {
                out.append(String(cString: cstr))
            }
        }
        return out
    }

    private func listColumns(db: OpaquePointer, table: String) -> [String] {
        var stmt: OpaquePointer?
        // table name embedded in SQL; storeaccountd table names are well-known
        // identifiers — no user input here.
        let q = "PRAGMA table_info(\"\(table)\")"
        guard sqlite3_prepare_v2(db, q, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var cols: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            // columns: cid(0), name(1), type(2), notnull(3), dflt_value(4), pk(5)
            if let nameCstr = sqlite3_column_text(stmt, 1) {
                let name = String(cString: nameCstr)
                let type = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? "?"
                cols.append("\(name) \(type)")
            }
        }
        return cols
    }

    private func countRows(db: OpaquePointer, table: String) -> Int {
        var stmt: OpaquePointer?
        let q = "SELECT COUNT(*) FROM \"\(table)\""
        guard sqlite3_prepare_v2(db, q, -1, &stmt, nil) == SQLITE_OK else { return -1 }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return -1 }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    // MARK: - plist dump

    private func dumpPlist(_ path: String) -> [String] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else {
            return ["[-] \(path)"]
        }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return ["[!] \(path) read failed"]
        }
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else {
            return ["[!] \(path) not a plist"]
        }
        var out = ["[+] \(path)"]
        out.append(contentsOf: describe(plist, indent: "    "))
        return out
    }

    /// recursively walks a plist value. strings longer than 24 chars are tail-redacted
    /// to keep tokens from leaking; numbers/booleans/dates render verbatim.
    private func describe(_ value: Any, indent: String) -> [String] {
        if let dict = value as? [String: Any] {
            var out: [String] = []
            for k in dict.keys.sorted() {
                let v = dict[k] as Any
                let head = "\(indent)\(k):"
                let body = describe(v, indent: indent + "  ")
                if body.count == 1 {
                    out.append("\(head) \(body[0].trimmingCharacters(in: .whitespaces))")
                } else {
                    out.append(head)
                    out.append(contentsOf: body)
                }
            }
            return out
        }
        if let array = value as? [Any] {
            var out = ["\(indent)[\(array.count) items]"]
            for (i, v) in array.enumerated().prefix(10) {
                out.append("\(indent)  [\(i)]:")
                out.append(contentsOf: describe(v, indent: indent + "    "))
            }
            if array.count > 10 {
                out.append("\(indent)  ... \(array.count - 10) more")
            }
            return out
        }
        if let s = value as? String {
            return [redactString(s)]
        }
        if let n = value as? NSNumber {
            return ["\(n)"]
        }
        if let d = value as? Date {
            return ["date(\(ISO8601DateFormatter().string(from: d)))"]
        }
        if let d = value as? Data {
            return ["data(\(d.count)B)"]
        }
        return ["?"]
    }

    private func redactString(_ s: String) -> String {
        if s.count <= 24 { return "\"\(s)\"" }
        let tail = s.suffix(4)
        return "\"<\(s.count) chars>...\(tail)\""
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
