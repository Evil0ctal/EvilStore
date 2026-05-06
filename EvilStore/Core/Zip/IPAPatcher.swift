// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import Foundation
import ZIPFoundation

/// adds iTunesMetadata.plist + per-binary sinf tickets to an .ipa in place.
/// without these patches Apple's installd refuses the package or the app
/// crashes at first launch.
///
/// strategy mirrors ApplePackage.SignatureInjector:
/// * if the ipa contains Manifest.plist with SinfPaths, write each sinf to
///   the matching path (multi-binary case: app + plugins).
/// * otherwise write a single sinf to SC_Info/<exe>.sinf (legacy case).
/// * always write iTunesMetadata.plist at the ipa root.
enum IPAPatcher {
    enum Error: Swift.Error {
        case openFailed
        case bundleNameMissing
        case missingInfoPlist
        case manifestParseFailed
        case sinfTargetExists(path: String)
        case writeFailed(path: String)
    }

    static func patch(
        ipaURL: URL,
        artifact: DownloadArtifact
    ) throws {
        guard let archive = Archive(url: ipaURL, accessMode: .update) else {
            throw Error.openFailed
        }

        let bundleName = try readBundleName(archive)

        if let manifest = try readManifest(archive, bundleName: bundleName) {
            try injectFromManifest(
                archive: archive,
                manifest: manifest,
                sinfs: artifact.sinfs,
                bundleName: bundleName
            )
        } else if let info = try readInfo(archive, bundleName: bundleName) {
            try injectFromInfo(
                archive: archive,
                info: info,
                sinfs: artifact.sinfs,
                bundleName: bundleName
            )
        } else {
            throw Error.missingInfoPlist
        }

        try injectMetadata(archive: archive, blob: artifact.iTunesMetadata)
    }

    // MARK: - read

    private static func readBundleName(_ archive: Archive) throws -> String {
        for entry in archive {
            let path = entry.path
            guard path.contains(".app/Info.plist"), !path.contains("/Watch/") else { continue }
            let parts = path.split(separator: "/")
            // expect: Payload/<App>.app/Info.plist
            guard parts.count >= 2 else { continue }
            let appComponent = parts[parts.count - 2]
            return String(appComponent.replacingOccurrences(of: ".app", with: ""))
        }
        throw Error.bundleNameMissing
    }

    private static func readEntryData(_ archive: Archive, path: String) throws -> Data {
        guard let entry = archive[path] else {
            throw Error.missingInfoPlist
        }
        var buffer = Data()
        _ = try archive.extract(entry) { chunk in buffer.append(chunk) }
        return buffer
    }

    private static func readManifest(_ archive: Archive, bundleName: String) throws -> Manifest? {
        let path = "Payload/\(bundleName).app/SC_Info/Manifest.plist"
        guard archive[path] != nil else { return nil }
        let data = try readEntryData(archive, path: path)
        return try? PropertyListDecoder().decode(Manifest.self, from: data)
    }

    private static func readInfo(_ archive: Archive, bundleName: String) throws -> Info? {
        let path = "Payload/\(bundleName).app/Info.plist"
        guard archive[path] != nil else { return nil }
        let data = try readEntryData(archive, path: path)
        return try? PropertyListDecoder().decode(Info.self, from: data)
    }

    // MARK: - write

    private static func injectFromManifest(
        archive: Archive,
        manifest: Manifest,
        sinfs: [Sinf],
        bundleName: String
    ) throws {
        for (index, sinfPath) in manifest.sinfPaths.enumerated() {
            guard index < sinfs.count else { break }
            let target = "Payload/\(bundleName).app/\(sinfPath)"
            try addEntry(archive: archive, path: target, data: sinfs[index].data)
        }
    }

    private static func injectFromInfo(
        archive: Archive,
        info: Info,
        sinfs: [Sinf],
        bundleName: String
    ) throws {
        guard let sinf = sinfs.first else { return }
        let target = "Payload/\(bundleName).app/SC_Info/\(info.bundleExecutable).sinf"
        try addEntry(archive: archive, path: target, data: sinf.data)
    }

    private static func injectMetadata(archive: Archive, blob: Data) throws {
        try addEntry(archive: archive, path: "iTunesMetadata.plist", data: blob, replace: true)
    }

    /// helper: append a file entry with deflate compression, optionally
    /// removing a pre-existing entry at the same path so re-patching works.
    private static func addEntry(
        archive: Archive,
        path: String,
        data: Data,
        replace: Bool = false
    ) throws {
        if let existing = archive[path] {
            if replace {
                try archive.remove(existing)
            } else {
                throw Error.sinfTargetExists(path: path)
            }
        }
        do {
            try archive.addEntry(
                with: path,
                type: .file,
                uncompressedSize: Int64(data.count),
                compressionMethod: .deflate
            ) { position, size -> Data in
                let start = data.startIndex.advanced(by: Int(position))
                let end = start.advanced(by: size)
                return data.subdata(in: start ..< end)
            }
        } catch {
            throw Error.writeFailed(path: path)
        }
    }
}

private struct Manifest: Decodable {
    let sinfPaths: [String]
    enum CodingKeys: String, CodingKey { case sinfPaths = "SinfPaths" }
}

private struct Info: Decodable {
    let bundleExecutable: String
    enum CodingKeys: String, CodingKey { case bundleExecutable = "CFBundleExecutable" }
}
