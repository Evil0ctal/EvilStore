// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import Foundation

struct Unimplemented: Error, CustomStringConvertible {
    let symbol: String
    var description: String { "unimplemented: \(symbol)" }
}

func unimplemented(_ symbol: String = #function) -> Never {
    fatalError("unimplemented: \(symbol)")
}

func unimplementedThrowing(_ symbol: String = #function) throws -> Never {
    throw Unimplemented(symbol: symbol)
}
