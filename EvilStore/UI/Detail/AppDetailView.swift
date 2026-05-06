// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import SwiftUI

/// app detail with the version timeline that drives the whole product. m2 ships
/// header + external-id timeline. m2.5 fills in display version + release date
/// via the partial-zip Info.plist peek. m3 adds the Download button.
struct AppDetailView: View {
    @StateObject private var vm: AppDetailViewModel
    @EnvironmentObject private var accountStore: AccountStore

    init(app: App) {
        _vm = StateObject(wrappedValue: AppDetailViewModel(app: app))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                Divider()
                versionsSection
            }
            .padding(16)
        }
        .navigationTitle(vm.app.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task { await vm.load(account: accountStore.active) }
        }
        .onChange(of: accountStore.active) { _ in
            Task { await vm.load(account: accountStore.active) }
        }
    }

    // MARK: - header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            DetailArtwork(url: vm.app.artworkURL)
                .frame(width: 84, height: 84)
                .cornerRadius(18)
            VStack(alignment: .leading, spacing: 4) {
                Text(vm.app.name)
                    .font(.title3.bold())
                Text(vm.app.artistName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("\(vm.app.version) · \(vm.app.formattedPrice)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(vm.app.bundleID)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
    }

    // MARK: - versions

    private var versionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader
            content
        }
    }

    private var sectionHeader: some View {
        HStack {
            Text("VERSIONS")
                .font(.caption.bold())
                .foregroundColor(.secondary)
            Spacer()
            if case .loaded = vm.state {
                Text("\(vm.versions.count) total")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .idle, .loading:
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .padding(.vertical, 24)
        case .noSession:
            sessionMissingView
        case .loaded:
            if vm.versions.isEmpty {
                Text("no version history available for this app on this account")
                    .font(.callout)
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(vm.versions) { v in
                        VersionRow(
                            info: v,
                            isLatest: v.externalIdentifier == vm.versions.first?.externalIdentifier,
                            isSelected: v.externalIdentifier == vm.selectedVersionID
                        ) {
                            vm.selectedVersionID = v.externalIdentifier
                        }
                    }
                }
            }
        case let .failed(message):
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundColor(.orange)
                Button("retry") {
                    Task { await vm.load(account: accountStore.active) }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(8)
            }
            .font(.callout)
        }
    }

    private var sessionMissingView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("no system session yet", systemImage: "key")
                .font(.callout)
                .foregroundColor(.secondary)
            Text(
                "EvilStore borrows the App Store session at launch. if probing failed, try Settings › Stealth diagnostics."
            )
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }
}

private struct VersionRow: View {
    let info: VersionInfo
    let isLatest: Bool
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 0) {
                    Circle()
                        .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.4))
                        .frame(width: 10, height: 10)
                        .padding(.top, 6)
                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
                .frame(width: 12)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(info.displayVersion ?? "ext \(info.externalIdentifier)")
                            .font(.body.monospacedDigit())
                            .foregroundColor(.primary)
                        if isLatest {
                            Text("latest")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15))
                                .foregroundColor(.accentColor)
                                .cornerRadius(4)
                        }
                    }
                    if let displayVersion = info.displayVersion {
                        Text("ext \(info.externalIdentifier)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    if let releaseDate = info.releaseDate {
                        Text(releaseDate, style: .date)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    if isSelected {
                        Text("Download — coming in m3")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

private struct DetailArtwork: View {
    let url: URL?
    @State private var data: Data?
    @State private var loadedFor: URL?

    var body: some View {
        Group {
            if let data, let img = UIImage(data: data) {
                Image(uiImage: img).resizable()
            } else {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.secondary.opacity(0.18))
                    .overlay(
                        Image(systemName: "app")
                            .foregroundColor(.secondary)
                    )
            }
        }
        .onAppear { kick() }
        .onChange(of: url) { _ in
            data = nil
            loadedFor = nil
            kick()
        }
    }

    private func kick() {
        guard let url, loadedFor != url else { return }
        loadedFor = url
        Task {
            do {
                let (bytes, _) = try await URLSession.shared.data(from: url)
                await MainActor.run { data = bytes }
            } catch {
                // intentionally silent
            }
        }
    }
}
