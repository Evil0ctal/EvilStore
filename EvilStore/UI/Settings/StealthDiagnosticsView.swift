// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import SwiftUI
import UIKit

#if DEBUG

/// debug-only screen that runs all SystemSessionImporter strategies and
/// renders a redacted markdown report. exported via UIActivityViewController
/// for AirDrop to the developer mac.
///
/// per docs/4 §5: this view is the single deliverable that lets us populate
/// docs/m05_diagnostics/<ios-version>_<device>.md.
struct StealthDiagnosticsView: View {
    @State private var results: [PathResult] = []
    @State private var running: Bool = false
    @State private var lastReport: String = ""
    @State private var showShare: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                ForEach(results) { row(for: $0) }
                actions
                if !lastReport.isEmpty {
                    Text(lastReport)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.secondary.opacity(0.08))
                        .cornerRadius(8)
                }
            }
            .padding(16)
        }
        .navigationTitle("Stealth diagnostics")
        .onAppear { if results.isEmpty { run() } }
    }

    // MARK: - subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(deviceLine).font(.subheadline.bold())
            Text("evilstore \(buildLine)")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("redacted markdown export keeps secret tails (4 chars). do not paste full output anywhere public.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func row(for r: PathResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(symbol(r.status))
                    .font(.system(.body, design: .monospaced))
                Text("path \(r.code) — \(r.name)")
                    .font(.headline)
                Spacer()
                Text(r.status.rawValue)
                    .font(.caption.bold())
                    .foregroundColor(color(r.status))
            }
            Text(r.detail)
                .font(.system(.footnote, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                run()
            } label: {
                Label(running ? "running…" : "re-run", systemImage: "arrow.clockwise")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
            .disabled(running)
            .background(Color.secondary.opacity(0.15))
            .cornerRadius(8)

            Button {
                lastReport = renderMarkdown(results)
                showShare = true
            } label: {
                Label("export markdown", systemImage: "square.and.arrow.up")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
            .disabled(results.isEmpty)
            .background(Color.secondary.opacity(0.15))
            .cornerRadius(8)
        }
        .sheet(isPresented: $showShare) {
            ActivityView(items: [lastReport])
        }
    }

    // MARK: - probe

    private func run() {
        guard !running else { return }
        running = true
        results = []
        Task {
            let probes: [(code: String, name: String, importer: SystemSessionImporter)] = [
                ("A", "accountsd", AccountsdImporter()),
                ("B", "filesystem", FileSystemImporter()),
                ("C", "keychain", KeychainImporter()),
                // path D (xpc storeaccountd) intentionally unimplemented in m0.5
            ]
            var collected: [PathResult] = []
            for p in probes {
                let start = Date()
                let avail = await p.importer.isAvailable()
                guard avail else {
                    collected.append(PathResult(
                        code: p.code, name: p.name,
                        status: .denied,
                        detail: "isAvailable returned false",
                        elapsed: Date().timeIntervalSince(start)
                    ))
                    continue
                }
                do {
                    let acc = try await p.importer.snapshot()
                    collected.append(PathResult(
                        code: p.code, name: p.name,
                        status: .ok,
                        detail: summary(acc),
                        elapsed: Date().timeIntervalSince(start)
                    ))
                } catch {
                    collected.append(PathResult(
                        code: p.code, name: p.name,
                        status: .failed,
                        detail: "\(error)",
                        elapsed: Date().timeIntervalSince(start)
                    ))
                }
            }
            collected.append(PathResult(
                code: "D", name: "xpc storeaccountd",
                status: .skipped,
                detail: "not implemented in m0.5",
                elapsed: 0
            ))
            await MainActor.run {
                self.results = collected
                self.running = false
                self.lastReport = renderMarkdown(collected)
            }
        }
    }

    // MARK: - rendering

    private func summary(_ a: Account) -> String {
        let dsid = redactTail(a.directoryServicesIdentifier)
        let guid = a.guid.isEmpty ? "(empty)" : redactTail(a.guid)
        let token = a.passwordToken.map { redactTail($0) } ?? "nil"
        return """
        email      : \(a.email.isEmpty ? "(empty)" : a.email)
        dsid       : \(dsid)
        storefront : \(a.storefront)
        guid       : \(guid)
        token      : \(token)
        cookies    : \(a.cookies.count)
        """
    }

    private func renderMarkdown(_ rows: [PathResult]) -> String {
        var s = "# stealth probe report\n\n"
        s += "device     : \(deviceLine)\n"
        s += "evilstore  : \(buildLine)\n"
        s += "captured   : \(ISO8601DateFormatter().string(from: Date()))\n\n"
        for r in rows {
            s += "## path \(r.code) — \(r.name)\n"
            s += "status   : \(r.status.rawValue)\n"
            s += "elapsed  : \(Int(r.elapsed * 1000))ms\n"
            s += "detail   :\n"
            for line in r.detail.split(separator: "\n") {
                s += "  \(line)\n"
            }
            s += "\n"
        }
        return s
    }

    // MARK: - bits

    private var deviceLine: String {
        let device = UIDevice.current
        return "\(device.systemName) \(device.systemVersion) · \(device.model)"
    }

    private var buildLine: String {
        let info = Bundle.main.infoDictionary
        let mv = info?["CFBundleShortVersionString"] as? String ?? "?"
        let bv = info?["CFBundleVersion"] as? String ?? "?"
        return "\(mv) (build \(bv))"
    }

    private func symbol(_ s: PathStatus) -> String {
        switch s {
        case .ok:       return "[✓]"
        case .failed:   return "[✗]"
        case .denied:   return "[✗]"
        case .skipped:  return "[·]"
        }
    }

    private func color(_ s: PathStatus) -> Color {
        switch s {
        case .ok:       return .green
        case .failed:   return .red
        case .denied:   return .red
        case .skipped:  return .secondary
        }
    }
}

// MARK: - data

private enum PathStatus: String {
    case ok, failed, denied, skipped
}

private struct PathResult: Identifiable {
    let id = UUID()
    let code: String
    let name: String
    let status: PathStatus
    let detail: String
    let elapsed: TimeInterval
}

// MARK: - share sheet

private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

#endif
