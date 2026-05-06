// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import SwiftUI

@main
struct EvilStoreApp: SwiftUI.App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    private let services: AppServices

    init() {
        FileLayout.ensureDirs()
        services = AppServices()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(services.accountStore)
                .environmentObject(services.downloadService)
                .preferredColorScheme(.dark)
                .onAppear {
                    Task { await services.accountStore.bootstrap() }
                }
        }
    }
}

/// holds the app-wide singletons. main thread; constructed once on launch.
@MainActor
final class AppServices {
    let accountStore: AccountStore
    let downloadService: DownloadService

    init() {
        let accountStore = AccountStore()
        self.accountStore = accountStore
        downloadService = DownloadService(accountStore: accountStore)
    }
}
