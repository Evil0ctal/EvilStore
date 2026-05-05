// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import SwiftUI

/// placeholder Settings tab. M1 will replace with the §8 settings tree from
/// docs/3 ui design.
struct SettingsView: View {
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("DEBUG").font(.caption)) {
                    #if DEBUG
                    NavigationLink {
                        StealthDiagnosticsView()
                    } label: {
                        HStack {
                            Image(systemName: "stethoscope")
                                .foregroundColor(.accentColor)
                            Text("Stealth diagnostics")
                            Spacer()
                            Text("debug")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    #else
                    Text("debug-only entries hidden in release")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    #endif
                }

                Section(header: Text("ABOUT").font(.caption)) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(versionLabel).foregroundColor(.secondary)
                    }
                    HStack {
                        Text("License")
                        Spacer()
                        Text("GPL-2.0 only").foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }

    private var versionLabel: String {
        let info = Bundle.main.infoDictionary
        let mv = info?["CFBundleShortVersionString"] as? String ?? "?"
        let bv = info?["CFBundleVersion"] as? String ?? "?"
        return "\(mv) (build \(bv))"
    }
}
