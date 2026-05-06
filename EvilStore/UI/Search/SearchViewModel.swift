// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import Foundation

/// state for the Search tab. iOS 14 baseline = ObservableObject + @Published.
@MainActor
final class SearchViewModel: ObservableObject {
    enum LoadState: Equatable {
        case idle
        case searching
        case loaded
        case failed(String)
    }

    @Published var term: String = ""
    @Published var country: String = "US"
    @Published private(set) var results: [App] = []
    @Published private(set) var state: LoadState = .idle

    private let client: AppStoreClient
    private var inflight: Task<Void, Never>?
    /// debounce: only fire once the user stops typing for this long.
    private let debounce: UInt64 = 500_000_000 // 500 ms

    init(client: AppStoreClient = AppStoreClientLive()) {
        self.client = client
    }

    /// call from .onChange(of: term). debounces by `debounce` ns then runs.
    func termChanged(_ newValue: String) {
        inflight?.cancel()
        guard newValue.count >= 2 else {
            results = []
            state = .idle
            return
        }
        state = .searching
        inflight = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.debounce ?? 0)
            guard !Task.isCancelled else { return }
            await self?.run(term: newValue)
        }
    }

    func clear() {
        inflight?.cancel()
        term = ""
        results = []
        state = .idle
    }

    private func run(term: String) async {
        do {
            let apps = try await client.search(term: term, country: country, limit: 25)
            guard !Task.isCancelled else { return }
            results = apps
            state = .loaded
        } catch is CancellationError {
            return
        } catch {
            state = .failed(prettify(error))
        }
    }

    private func prettify(_ error: Error) -> String {
        if let urlErr = error as? URLError, urlErr.code == .notConnectedToInternet {
            return "couldn't reach Apple. check connection and try again."
        }
        return "\(error)"
    }
}
