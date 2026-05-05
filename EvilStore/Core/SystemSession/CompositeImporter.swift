// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import Foundation

/// chain importers; first success wins, all-fail throws .allPathsFailed
final class CompositeImporter: SystemSessionImporter {
    let name = "composite"
    private let strategies: [SystemSessionImporter]

    init(strategies: [SystemSessionImporter]) {
        self.strategies = strategies
    }

    func isAvailable() async -> Bool {
        for s in strategies where await s.isAvailable() {
            return true
        }
        return false
    }

    func snapshot() async throws -> Account {
        var failures: [String] = []
        for s in strategies {
            do {
                return try await s.snapshot()
            } catch {
                failures.append("\(s.name): \(error)")
            }
        }
        throw SystemSessionError.allPathsFailed(failures)
    }
}
