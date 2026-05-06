// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import SwiftUI

/// downloads tab. shows in-flight + done + failed tasks. M4 will plug an
/// "install" button on each .done row that hands the .ipa to TrollStore via
/// the apple-magnifier:// scheme.
struct DownloadsView: View {
    @EnvironmentObject private var service: DownloadService

    var body: some View {
        NavigationView {
            content
                .navigationTitle("Downloads")
                .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    @ViewBuilder
    private var content: some View {
        if service.tasks.isEmpty {
            emptyState
        } else {
            List {
                ForEach(service.tasks) { task in
                    DownloadRow(task: task) { service.cancel(taskID: $0) } onRemove: {
                        service.remove(taskID: $0)
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text("no downloads in flight")
                .foregroundColor(.secondary)
            Text("pick a version on the detail page to start a download")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
    }
}

private struct DownloadRow: View {
    let task: DownloadTask
    let onCancel: (UUID) -> Void
    let onRemove: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.app.name).font(.body)
                    Text(versionLine)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                statusButton
            }
            phaseSubview
        }
        .padding(.vertical, 4)
    }

    private var versionLine: String {
        let v = task.displayVersion ?? task.externalIdentifier ?? task.app.version
        return "\(v) · \(task.app.bundleID)"
    }

    @ViewBuilder
    private var phaseSubview: some View {
        switch task.phase {
        case .pending:
            Text("queued")
                .font(.caption)
                .foregroundColor(.secondary)
        case let .downloading(bytes, total):
            VStack(alignment: .leading, spacing: 4) {
                ProgressBar(value: total > 0 ? Double(bytes) / Double(total) : 0)
                    .frame(height: 4)
                Text(bytesLine(bytes: bytes, total: total))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        case .patching:
            HStack(spacing: 8) {
                ProgressView()
                Text("patching iTunesMetadata + sinfs")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        case let .done(localPath):
            VStack(alignment: .leading, spacing: 2) {
                Label("ready to install", systemImage: "checkmark.seal.fill")
                    .foregroundColor(.green)
                    .font(.caption)
                Text(localPath.lastPathComponent)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundColor(.orange)
        case .cancelled:
            Label("cancelled", systemImage: "xmark.circle")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var statusButton: some View {
        switch task.phase {
        case .pending, .downloading, .patching:
            Button("cancel") { onCancel(task.id) }
                .font(.caption)
                .buttonStyle(BorderlessButtonStyle())
        case .done, .failed, .cancelled:
            Button {
                onRemove(task.id)
            } label: {
                Image(systemName: "xmark")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(BorderlessButtonStyle())
        }
    }

    private func bytesLine(bytes: Int64, total: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let lhs = formatter.string(fromByteCount: bytes)
        if total > 0 {
            let rhs = formatter.string(fromByteCount: total)
            let pct = Int(Double(bytes) / Double(total) * 100)
            return "\(lhs) / \(rhs)  ·  \(pct)%"
        }
        return lhs
    }
}

private struct ProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(value))))
            }
            .clipShape(RoundedRectangle(cornerRadius: 2))
        }
    }
}
