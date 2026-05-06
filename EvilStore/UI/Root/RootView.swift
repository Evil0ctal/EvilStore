// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
            placeholder("Downloads")
                .tabItem { Label("Downloads", systemImage: "arrow.down.circle") }
            placeholder("Library")
                .tabItem { Label("Library", systemImage: "square.stack") }
            placeholder("Settings")
                .tabItem { Label("Settings", systemImage: "gear") }
        }
    }

    private func placeholder(_ title: String) -> some View {
        NavigationView {
            VStack(spacing: 16) {
                Image(systemName: "hammer")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("Hello, EvilStore")
                    .font(.title2.bold())
                Text("\(title) — coming soon")
                    .foregroundColor(.secondary)
            }
            .navigationTitle(title)
        }
    }
}

#if DEBUG
struct RootView_Previews: PreviewProvider {
    static var previews: some View {
        RootView()
            .preferredColorScheme(.dark)
    }
}
#endif
