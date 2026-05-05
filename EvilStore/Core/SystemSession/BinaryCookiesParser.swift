// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import Foundation

/// Apple Binary Cookies v0x100 reader.
///
/// File layout:
///   "cook" (4)
///   numPages (uint32 BE)
///   pageSizes[numPages] (uint32 BE each)
///   pages[numPages] (variable, sized as above)
///   checksum (8 BE) and footer ("\x07\x17\x20\x05\x00\x00\x4b\xb0") — both ignored on read
///
/// Page layout:
///   "\x00\x00\x01\x00" (page magic, LE in file but stable)
///   numCookies (uint32 LE)
///   cookieOffsets[numCookies] (uint32 LE each)
///   "\x00\x00\x00\x00" (page footer)
///   cookies (variable, addressed by cookieOffsets relative to page start)
///
/// Cookie record (all little-endian after the page magic):
///   size (uint32 LE)
///   "\x00\x00\x00\x00"
///   flags (uint32 LE; bit0 secure, bit2 httponly)
///   "\x00\x00\x00\x00"
///   urlOffset (uint32 LE)
///   nameOffset (uint32 LE)
///   pathOffset (uint32 LE)
///   valueOffset (uint32 LE)
///   "\x00" * 8 (end marker)
///   expires (Float64 LE, mac absolute time)
///   creation (Float64 LE, mac absolute time)
///   then 4 NUL-terminated UTF-8 strings at the offsets above
enum BinaryCookiesParser {
    enum ParseError: Error, Equatable {
        case fileTooSmall
        case badMagic
        case truncatedPage(index: Int)
        case truncatedCookie(page: Int, index: Int)
        case invalidString(field: String)
    }

    static func parse(at url: URL) throws -> [HTTPCookie] {
        let data = try Data(contentsOf: url)
        return try parse(data: data)
    }

    static func parse(data: Data) throws -> [HTTPCookie] {
        guard data.count >= 4 else { throw ParseError.fileTooSmall }
        guard data.prefix(4) == Data("cook".utf8) else { throw ParseError.badMagic }

        let numPages = try data.readUInt32BE(at: 4)
        var cursor = 8
        var pageSizes: [Int] = []
        pageSizes.reserveCapacity(Int(numPages))
        for _ in 0..<numPages {
            let size = try data.readUInt32BE(at: cursor)
            pageSizes.append(Int(size))
            cursor += 4
        }

        var out: [HTTPCookie] = []
        for (idx, size) in pageSizes.enumerated() {
            guard cursor + size <= data.count else {
                throw ParseError.truncatedPage(index: idx)
            }
            let pageData = data.subdata(in: cursor..<(cursor + size))
            out.append(contentsOf: try parsePage(pageData, pageIndex: idx))
            cursor += size
        }
        return out
    }

    private static func parsePage(_ page: Data, pageIndex: Int) throws -> [HTTPCookie] {
        // page magic 0x00000100 (read as LE uint32 == 256)
        guard page.count >= 8 else { throw ParseError.truncatedPage(index: pageIndex) }
        let numCookies = Int(try page.readUInt32LE(at: 4))
        var offsets: [Int] = []
        offsets.reserveCapacity(numCookies)
        for i in 0..<numCookies {
            offsets.append(Int(try page.readUInt32LE(at: 8 + i * 4)))
        }

        var out: [HTTPCookie] = []
        for (i, off) in offsets.enumerated() {
            guard let cookie = try parseCookie(page: page, at: off, pageIndex: pageIndex, cookieIndex: i) else {
                continue
            }
            out.append(cookie)
        }
        return out
    }

    private static func parseCookie(page: Data, at off: Int, pageIndex: Int, cookieIndex: Int) throws -> HTTPCookie? {
        // need at least 56 bytes for the fixed header
        guard off + 56 <= page.count else {
            throw ParseError.truncatedCookie(page: pageIndex, index: cookieIndex)
        }
        let flags = try page.readUInt32LE(at: off + 8)
        let urlOff = Int(try page.readUInt32LE(at: off + 16))
        let nameOff = Int(try page.readUInt32LE(at: off + 20))
        let pathOff = Int(try page.readUInt32LE(at: off + 24))
        let valueOff = Int(try page.readUInt32LE(at: off + 28))
        let expiresMac = try page.readFloat64LE(at: off + 40)
        // creation at off + 48 — not used by HTTPCookie

        guard let url = readCString(page, at: off + urlOff) else {
            throw ParseError.invalidString(field: "url")
        }
        guard let name = readCString(page, at: off + nameOff) else {
            throw ParseError.invalidString(field: "name")
        }
        guard let path = readCString(page, at: off + pathOff) else {
            throw ParseError.invalidString(field: "path")
        }
        guard let value = readCString(page, at: off + valueOff) else {
            throw ParseError.invalidString(field: "value")
        }

        var props: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: url,
            .path: path,
        ]
        if (flags & 0x1) != 0 { props[.secure] = "TRUE" }
        // httponly via flag bit 2 has no public HTTPCookie key on iOS; we set isHTTPOnly via init param if needed
        if expiresMac > 0 {
            props[.expires] = Date(timeIntervalSinceReferenceDate: expiresMac)
        }
        return HTTPCookie(properties: props)
    }

    private static func readCString(_ data: Data, at off: Int) -> String? {
        guard off >= 0, off < data.count else { return nil }
        var end = off
        while end < data.count, data[end] != 0 { end += 1 }
        let bytes = data.subdata(in: off..<end)
        return String(data: bytes, encoding: .utf8)
    }
}

private extension Data {
    func readUInt32BE(at offset: Int) throws -> UInt32 {
        guard offset + 4 <= count else {
            throw BinaryCookiesParser.ParseError.fileTooSmall
        }
        let b0 = UInt32(self[offset])
        let b1 = UInt32(self[offset + 1])
        let b2 = UInt32(self[offset + 2])
        let b3 = UInt32(self[offset + 3])
        return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
    }

    func readUInt32LE(at offset: Int) throws -> UInt32 {
        guard offset + 4 <= count else {
            throw BinaryCookiesParser.ParseError.fileTooSmall
        }
        let b0 = UInt32(self[offset])
        let b1 = UInt32(self[offset + 1])
        let b2 = UInt32(self[offset + 2])
        let b3 = UInt32(self[offset + 3])
        return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
    }

    func readFloat64LE(at offset: Int) throws -> TimeInterval {
        guard offset + 8 <= count else {
            throw BinaryCookiesParser.ParseError.fileTooSmall
        }
        var bits: UInt64 = 0
        for i in 0..<8 {
            bits |= UInt64(self[offset + i]) << (UInt64(i) * 8)
        }
        return Double(bitPattern: bits)
    }
}
