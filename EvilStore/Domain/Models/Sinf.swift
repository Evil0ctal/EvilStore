// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import Foundation

/// per-binary signature ticket from Apple's storefront. one Sinf per Mach-O
/// inside the .app bundle (the main binary plus any plug-ins/extensions).
struct Sinf: Equatable {
    let id: Int64
    let data: Data
}
