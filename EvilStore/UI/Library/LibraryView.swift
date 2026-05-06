// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import SwiftUI

/// library tab. lists patched .ipa files sitting in EvilStore/Downloads/
/// grouped by bundle id. each row offers Install (TrollStore handoff),
/// Share (UIActivityViewController), and Delete.
struct LibraryView: View {
    @StateObject private var service = LibraryService()
    @State private var shareItem: ShareItem?
    @State private var alert: AlertContent?

    private let bridge: TrollStoreBridge = TrollStoreBridgeLive()

    var body: some View {
        NavigationView {
            content
                .navigationTitle("Library")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            service.refresh()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
                .onAppear { service.refresh() }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .sheet(item: $shareItem) { item in
            ActivityShareSheet(items: [item.url])
        }
        .alert(item: $alert) { content in
            Alert(
                title: Text(content.title),
                message: Text(content.message),
                dismissButton: .default(Text("ok"))
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        if service.entries.isEmpty {
            emptyState
        } else {
            List {
                ForEach(service.grouped(), id: \.bundleID) { group in
                    Section(header: Text(group.bundleID)) {
                        ForEach(group.items) { entry in
                            LibraryRow(
                                entry: entry,
                                onInstall: { install(entry) },
                                onShare: { shareItem = ShareItem(url: entry.fileURL) },
                                onDelete: { service.delete(entry) }
                            )
                        }
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "square.stack")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text("no ipas in your library")
                .foregroundColor(.secondary)
            Text("finished downloads land here so you can re-install without re-downloading")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
    }

    private func install(_ entry: LibraryEntry) {
        guard bridge.isAvailable() else {
            alert = AlertContent(
                title: "TrollStore not detected",
                message: "the apple-magnifier:// scheme is not handled on this device. install TrollStore 1.3 or newer first."
            )
            return
        }
        if !bridge.install(ipaAt: entry.fileURL) {
            alert = AlertContent(
                title: "couldn't open TrollStore",
                message: "the URL scheme call failed. AirDrop the .ipa to TrollStore manually as a fallback."
            )
        }
    }
}

private struct LibraryRow: View {
    let entry: LibraryEntry
    let onInstall: () -> Void
    let onShare: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.displayVersion ?? "unknown")
                    .font(.body.monospacedDigit())
                Spacer()
                Text(byteFormatter.string(fromByteCount: entry.fileSize))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(entry.fileURL.lastPathComponent)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: 8) {
                Button("install", action: onInstall)
                    .buttonStyle(BorderlessButtonStyle())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .foregroundColor(.white)
                    .background(Color.accentColor)
                    .cornerRadius(6)
                Button("share", action: onShare)
                    .buttonStyle(BorderlessButtonStyle())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.secondary.opacity(0.15))
                    .cornerRadius(6)
                Spacer()
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
        }
        .padding(.vertical, 4)
    }

    private var byteFormatter: ByteCountFormatter {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }
}

// MARK: - helpers

private struct AlertContent: Identifiable {
    var id: String {
        title + message
    }

    let title: String
    let message: String
}

private struct ShareItem: Identifiable {
    var id: String {
        url.absoluteString
    }

    let url: URL
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}
