// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import UIKit

/// hands a patched .ipa over to TrollStore via the URL scheme it owns since
/// 1.3. TrollStore replaces the system "Magnifier" app and registers
/// apple-magnifier:// to dodge bundle-id-based jailbreak detections.
///
/// the scheme accepts:
///   apple-magnifier://install?url=<file://path/to/foo.ipa>
///   apple-magnifier://enable-jit?bundle-id=<id>
@MainActor
protocol TrollStoreBridge {
    /// true on devices that have TrollStore 1.3+ installed (or the system
    /// Magnifier app on iPhones without TrollStore — we can't tell apart
    /// from canOpenURL alone, but the install request just no-ops on
    /// vanilla devices).
    func isAvailable() -> Bool

    /// returns false if the URL scheme could not be opened at all.
    /// success/failure of the install itself is reported by TrollStore in
    /// its own UI; we don't get a callback.
    @discardableResult
    func install(ipaAt url: URL) -> Bool
}

@MainActor
struct TrollStoreBridgeLive: TrollStoreBridge {
    private let app: UIApplication
    private let probe = URL(string: "apple-magnifier://")!

    init(app: UIApplication = .shared) {
        self.app = app
    }

    func isAvailable() -> Bool {
        app.canOpenURL(probe)
    }

    @discardableResult
    func install(ipaAt url: URL) -> Bool {
        guard var comps = URLComponents(string: "apple-magnifier://install") else {
            return false
        }
        comps.queryItems = [.init(name: "url", value: url.absoluteString)]
        guard let target = comps.url else { return false }
        guard app.canOpenURL(target) else { return false }
        app.open(target, options: [:], completionHandler: nil)
        return true
    }
}
