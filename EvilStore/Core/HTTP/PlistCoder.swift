// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import Foundation

/// thin wrapper around PropertyListSerialization. apple's storefront accepts
/// both binary and xml plist on the auth endpoint but only xml on the
/// download/list endpoints (verified via ApplePackage), so we always send xml.
enum PlistCoder {
    static func encodeXML(_ value: Any) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
    }

    static func decode(_ data: Data) throws -> [String: Any] {
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let dict = plist as? [String: Any] else {
            throw NSError(domain: "PlistCoder", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "response is not a dictionary"
            ])
        }
        return dict
    }
}
