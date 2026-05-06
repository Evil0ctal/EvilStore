// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import Foundation

/// state of one download in the queue. the engine produces progress; the
/// service moves the task through patching -> done. the UI binds to this.
struct DownloadTask: Identifiable, Equatable {
    enum Phase: Equatable {
        case pending
        case downloading(bytes: Int64, total: Int64)
        case patching
        case done(localPath: URL)
        case failed(message: String)
        case cancelled
    }

    let id: UUID
    let app: App
    let externalIdentifier: String?
    /// resolved by Download.run before the engine starts streaming
    var displayVersion: String?
    var releaseDate: Date?
    var localPath: URL?
    var phase: Phase
    var startedAt: Date

    init(
        id: UUID = UUID(),
        app: App,
        externalIdentifier: String?,
        displayVersion: String? = nil,
        releaseDate: Date? = nil,
        phase: Phase = .pending,
        startedAt: Date = Date()
    ) {
        self.id = id
        self.app = app
        self.externalIdentifier = externalIdentifier
        self.displayVersion = displayVersion
        self.releaseDate = releaseDate
        localPath = nil
        self.phase = phase
        self.startedAt = startedAt
    }
}
