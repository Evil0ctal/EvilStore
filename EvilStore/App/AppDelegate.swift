// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // smoke log so we know entitlements didn't reject the process
        NSLog("[EvilStore] launched. bundle=%@", Bundle.main.bundleIdentifier ?? "?")
        return true
    }

    // URL scheme entry; Router takes over after M1
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        NSLog("[EvilStore] open url: %@", url.absoluteString)
        return true
    }
}
