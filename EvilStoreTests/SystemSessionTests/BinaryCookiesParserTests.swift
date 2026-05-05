// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import XCTest
@testable import EvilStore

final class BinaryCookiesParserTests: XCTestCase {
    func test_parse_sample_returns_two_cookies() throws {
        let url = try fixtureURL("sample.binarycookies")
        let cookies = try BinaryCookiesParser.parse(at: url)
        XCTAssertEqual(cookies.count, 2)

        let session = cookies.first { $0.name == "session" }
        XCTAssertNotNil(session)
        XCTAssertEqual(session?.value, "abc123")
        XCTAssertEqual(session?.domain, "buy.itunes.apple.com")
        XCTAssertEqual(session?.path, "/")
        XCTAssertTrue(session?.isSecure ?? false)

        let token = cookies.first { $0.name == "X-Token" }
        XCTAssertNotNil(token)
        XCTAssertEqual(token?.value, "T-EX-FIXED")
    }

    func test_bad_magic_throws() {
        let bogus = Data("nope".utf8) + Data(count: 100)
        XCTAssertThrowsError(try BinaryCookiesParser.parse(data: bogus)) { error in
            XCTAssertEqual(error as? BinaryCookiesParser.ParseError, .badMagic)
        }
    }

    func test_too_small_throws() {
        let tiny = Data([0x01, 0x02])
        XCTAssertThrowsError(try BinaryCookiesParser.parse(data: tiny)) { error in
            XCTAssertEqual(error as? BinaryCookiesParser.ParseError, .fileTooSmall)
        }
    }

    private func fixtureURL(_ name: String) throws -> URL {
        let bundle = Bundle(for: type(of: self))
        if let url = bundle.url(forResource: name, withExtension: nil, subdirectory: "Fixtures") {
            return url
        }
        // when fixtures land at the bundle root because xcodegen flattens the folder
        if let url = bundle.url(forResource: name, withExtension: nil) {
            return url
        }
        throw XCTSkip("fixture missing in test bundle: \(name)")
    }
}
