// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import Foundation

/// runs DownloadTasks one at a time. for each task:
///   1. AppStoreClient.download() resolves URL + sinfs + metadata
///   2. DownloadEngine streams the .ipa to disk reporting progress
///   3. IPAPatcher injects iTunesMetadata.plist + sinf tickets in place
///   4. task moves to .done with the patched ipa path
@MainActor
final class DownloadService: ObservableObject {
    @Published private(set) var tasks: [DownloadTask] = []

    private let client: AppStoreClient
    private let engine: DownloadEngine
    private let accountStore: AccountStore
    private var processing: Task<Void, Never>?
    private var tokens: [UUID: TaskCancellationToken] = [:]

    init(
        client: AppStoreClient = AppStoreClientLive(),
        engine: DownloadEngine = DownloadEngine(),
        accountStore: AccountStore
    ) {
        self.client = client
        self.engine = engine
        self.accountStore = accountStore
    }

    func enqueue(app: App, externalIdentifier: String?, displayVersion: String?) {
        let task = DownloadTask(
            app: app,
            externalIdentifier: externalIdentifier,
            displayVersion: displayVersion
        )
        tasks.append(task)
        kick()
    }

    func cancel(taskID: UUID) {
        tokens[taskID]?.cancel()
        if let idx = tasks.firstIndex(where: { $0.id == taskID }) {
            switch tasks[idx].phase {
            case .pending, .downloading, .patching:
                tasks[idx].phase = .cancelled
            default:
                break
            }
        }
    }

    func remove(taskID: UUID) {
        tokens[taskID]?.cancel()
        tokens.removeValue(forKey: taskID)
        tasks.removeAll { $0.id == taskID }
    }

    // MARK: - private

    private func kick() {
        guard processing == nil else { return }
        processing = Task { [weak self] in
            await self?.runLoop()
            await MainActor.run { self?.processing = nil }
        }
    }

    private func runLoop() async {
        while let nextID = nextPendingID() {
            await process(taskID: nextID)
        }
    }

    private func nextPendingID() -> UUID? {
        tasks.first { task in
            if case .pending = task.phase { return true }
            return false
        }?.id
    }

    private func process(taskID: UUID) async {
        guard let account = accountStore.active else {
            update(taskID: taskID) {
                $0.phase = .failed(message: "no system session — open Settings › Stealth diagnostics")
            }
            return
        }
        guard let task = task(for: taskID) else { return }
        let token = TaskCancellationToken()
        tokens[taskID] = token

        let artifact: DownloadArtifact
        do {
            artifact = try await client.download(
                externalIdentifier: task.externalIdentifier,
                account: account,
                app: task.app
            )
        } catch let err as Download.Error {
            update(taskID: taskID) { $0.phase = .failed(message: format(err)) }
            return
        } catch {
            update(taskID: taskID) { $0.phase = .failed(message: "\(error)") }
            return
        }

        let dest = FileLayout.downloadDestination(
            app: task.app,
            displayVersion: artifact.displayVersion ?? task.displayVersion
        )
        update(taskID: taskID) {
            $0.displayVersion = artifact.displayVersion ?? $0.displayVersion
            $0.releaseDate = artifact.releaseDate ?? $0.releaseDate
            $0.localPath = dest
            $0.phase = .downloading(bytes: 0, total: 0)
        }

        for await event in engine.stream(from: artifact.ipaURL, to: dest, token: token) {
            switch event {
            case let .progress(bytes, total):
                update(taskID: taskID) {
                    if case .downloading = $0.phase {
                        $0.phase = .downloading(bytes: bytes, total: total)
                    }
                }
            case .finished:
                update(taskID: taskID) { $0.phase = .patching }
                do {
                    try IPAPatcher.patch(ipaURL: dest, artifact: artifact)
                    update(taskID: taskID) { $0.phase = .done(localPath: dest) }
                } catch {
                    try? FileManager.default.removeItem(at: dest)
                    update(taskID: taskID) {
                        $0.phase = .failed(message: "patch failed: \(error)")
                    }
                }
            case let .failed(error):
                if case DownloadEngine.Error.cancelled = error {
                    update(taskID: taskID) { $0.phase = .cancelled }
                } else {
                    update(taskID: taskID) { $0.phase = .failed(message: "\(error)") }
                }
            }
        }
    }

    private func task(for id: UUID) -> DownloadTask? {
        tasks.first { $0.id == id }
    }

    private func update(taskID: UUID, _ mutate: (inout DownloadTask) -> Void) {
        guard let idx = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        var copy = tasks[idx]
        mutate(&copy)
        tasks[idx] = copy
    }

    private func format(_ err: Download.Error) -> String {
        switch err {
        case let .http(status):
            return "http \(status). retry, or refresh the system session."
        case let .unexpectedShape(detail):
            return "apple changed the response shape: \(detail)"
        case .tokenExpired:
            return "session expired. open Settings › Apple ID, sign out + in, relaunch."
        case .licenseRequired:
            return "no license for this app on this account. buy it on apple's site first."
        case let .failure(failureType, customerMessage):
            return customerMessage ?? "failure \(failureType)"
        case .metadataEncoding:
            return "couldn't encode iTunesMetadata.plist — internal bug"
        }
    }
}
