// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import SwiftUI

@main
struct EvilStoreApp: SwiftUI.App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var accountStore = AccountStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(accountStore)
                .preferredColorScheme(.dark)
                .onAppear {
                    Task { await accountStore.bootstrap() }
                }
        }
    }
}
