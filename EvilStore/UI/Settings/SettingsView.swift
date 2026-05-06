// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import SwiftUI

/// settings tab. m1 placeholder; future milestones expand this with manual
/// account management, GUID export, log export.
struct SettingsView: View {
    @EnvironmentObject private var accountStore: AccountStore

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("ACCOUNT").font(.caption)) {
                    accountSummary
                    NavigationLink {
                        StealthDiagnosticsView()
                    } label: {
                        HStack {
                            Image(systemName: "stethoscope")
                                .foregroundColor(.accentColor)
                            Text("Stealth diagnostics")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Button {
                        Task { await accountStore.bootstrap(force: true) }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Re-probe stealth paths")
                        }
                    }
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
        .navigationViewStyle(StackNavigationViewStyle())
    }

    @ViewBuilder
    private var accountSummary: some View {
        switch accountStore.state {
        case .idle:
            Label("not probed yet", systemImage: "circle")
                .foregroundColor(.secondary)
        case .probing:
            HStack(spacing: 8) {
                ProgressView()
                Text("probing system app store")
                    .foregroundColor(.secondary)
            }
        case .ready:
            VStack(alignment: .leading, spacing: 2) {
                Label("borrowed system session", systemImage: "checkmark.seal")
                    .foregroundColor(.green)
                if let acc = accountStore.active {
                    Text(acc.email.isEmpty ? "(no email)" : acc.email)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("storefront: \(acc.storefront)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        case .noSession:
            VStack(alignment: .leading, spacing: 4) {
                Label("not logged in to App Store", systemImage: "questionmark.circle")
                    .foregroundColor(.orange)
                Text("open Settings › Apple ID, sign in, then re-probe.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        case let .failed(message):
            VStack(alignment: .leading, spacing: 4) {
                Label("stealth probe failed", systemImage: "exclamationmark.triangle")
                    .foregroundColor(.red)
                Text(message)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(4)
            }
        }
    }

    private var versionLabel: String {
        let info = Bundle.main.infoDictionary
        let mv = info?["CFBundleShortVersionString"] as? String ?? "?"
        let bv = info?["CFBundleVersion"] as? String ?? "?"
        return "\(mv) (build \(bv))"
    }
}
