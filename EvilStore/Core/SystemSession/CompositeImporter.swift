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
                let acc = try await s.snapshot()
                NSLog("[EvilStore] stealth path %@: ok", s.name)
                return acc
            } catch {
                let line = "\(s.name): \(error)"
                NSLog("[EvilStore] stealth path %@", line)
                failures.append(line)
            }
        }
        throw SystemSessionError.allPathsFailed(failures)
    }
}
