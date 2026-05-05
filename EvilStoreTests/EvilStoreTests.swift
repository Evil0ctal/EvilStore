// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import XCTest
@testable import EvilStore

final class EvilStoreSmokeTests: XCTestCase {
    func test_bundleIdentifier_isExpected() {
        // runs in test host; Bundle.main is the test runner — placeholder only
        XCTAssertNotNil(Bundle.main.bundleIdentifier)
    }
}
