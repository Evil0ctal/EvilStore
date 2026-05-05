// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import Foundation

/// rate-limit gate. ensures at least `minInterval` seconds elapse between
/// successive calls to wait(). storefront calls share one instance per client
/// because Apple's WAF rate-limits at ~3 req/s on Configurator UA.
actor AsyncThrottle {
    private let minInterval: TimeInterval
    private var lastSent: Date?

    init(minInterval: TimeInterval) {
        self.minInterval = minInterval
    }

    func wait() async {
        if let last = lastSent {
            let elapsed = Date().timeIntervalSince(last)
            if elapsed < minInterval {
                let napNs = UInt64((minInterval - elapsed) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: napNs)
            }
        }
        lastSent = Date()
    }
}
