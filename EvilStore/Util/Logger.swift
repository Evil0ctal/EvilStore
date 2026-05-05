// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

import Foundation

/// fields that must be redacted in any log line — see 2-doc §7.4.
/// the redaction is best effort: callers should not pass secrets through Logger
/// in the first place. this is a second line of defence.
enum SensitiveField: String, CaseIterable {
    case password
    case passwordToken
    case oauthToken
    case dsid
    case altDSID
    case guid
    case cookie
}

/// keep tail-N of a secret-bearing string so diagnostics reports remain useful while
/// not leaking the secret. used by Account.debugDescription and the diagnostics view.
func redactTail(_ s: String, keep: Int = 4) -> String {
    guard s.count > keep else { return String(repeating: "•", count: s.count) }
    return String(repeating: "•", count: s.count - keep) + s.suffix(keep)
}

/// drop-in for NSLog with field-level scrubbing. when a known sensitive field
/// name appears in `message`, replace its value with "<field>" so logs uploaded
/// for triage do not leak.
enum Log {
    static func info(_ message: String, scrubbing fields: [SensitiveField] = []) {
        var clean = message
        for f in fields {
            // crude but effective: replace `<field>=<rest-of-token>` up to whitespace or comma
            clean = scrub(clean, field: f.rawValue)
        }
        NSLog("[EvilStore] %@", clean)
    }

    private static func scrub(_ s: String, field: String) -> String {
        // matches "<field>=value" (value runs until whitespace, comma, or close-paren/bracket)
        guard let regex = try? NSRegularExpression(
            pattern: "(\(field))=([^\\s,)\\]]+)",
            options: [.caseInsensitive]
        ) else {
            return s
        }
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        return regex.stringByReplacingMatches(
            in: s, options: [], range: range, withTemplate: "$1=<redacted>"
        )
    }
}
