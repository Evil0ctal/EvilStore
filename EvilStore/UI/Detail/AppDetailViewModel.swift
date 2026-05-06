// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import Foundation

@MainActor
final class AppDetailViewModel: ObservableObject {
    enum LoadState: Equatable {
        case idle
        case noSession
        case loading
        case loaded
        case failed(String)
    }

    let app: App

    @Published private(set) var versions: [VersionInfo] = []
    @Published private(set) var state: LoadState = .idle
    @Published var selectedVersionID: String?

    private let client: AppStoreClient

    init(app: App, client: AppStoreClient = AppStoreClientLive()) {
        self.app = app
        self.client = client
    }

    func load(account: Account?) async {
        guard let account else {
            state = .noSession
            versions = []
            return
        }
        state = .loading
        do {
            let ids = try await client.listVersions(account: account, app: app)
            versions = ids.map { VersionInfo(externalIdentifier: $0) }
            selectedVersionID = versions.first?.externalIdentifier
            state = .loaded
        } catch let err as ListVersions.Error {
            state = .failed(format(err))
        } catch {
            state = .failed("\(error)")
        }
    }

    private func format(_ err: ListVersions.Error) -> String {
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
        }
    }
}
