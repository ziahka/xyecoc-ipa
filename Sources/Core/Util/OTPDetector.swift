//
//  OTPDetector.swift
//  XyecocMail
//
//  Extracts one-time verification codes (4–8 digits) from the rendered HTML
//  of an email. Pure Foundation, no state — used by MailReaderView to show a
//  "copy code" chip above the message body. The candidate number must appear
//  near a keyword ("код", "code", "otp", …) inside the plain-text projection
//  of the letter, which keeps dates, order numbers and phone fragments out.
//

import Foundation

enum OTPDetector {

    private static let keywords: [String] = [
        "код", "code", "otp", "one-time", "one time",
        "одноразов", "подтвержде", "верификац",
        "verification", "verify", "confirm", "security",
        "пароль", "password", "pin"
    ]

    /// Maximum distance (in plain-text characters) between the keyword and
    /// the candidate digits.
    private static let contextWindow = 120

    /// Extracts the most probable verification code, or nil when the letter
    /// contains none. Prefers 6-digit codes that sit close to a keyword.
    static func extractCode(from html: String) -> String? {
        let text = plainText(from: html)
        guard !text.isEmpty else { return nil }

        guard let regex = try? NSRegularExpression(pattern: "\\b\\d{4,8}\\b") else { return nil }
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, range: fullRange)
        guard !matches.isEmpty else { return nil }

        let lowered = text.lowercased() as NSString

        var bestCode: String?
        var bestScore = Int.min

        for match in matches {
            let code = nsText.substring(with: match.range)

            // Skip year-like 4-digit numbers (2020…2029, 1990…1999).
            if code.count == 4, isYearLike(code) { continue }
            // Skip digits glued to letters or punctuation-only surroundings
            // (e.g. "ID123456", "#123456") — codes are standalone tokens and
            // \\b already guarantees a letter/digit boundary on both sides.
            if match.range.location > 0 {
                let prev = lowered.substring(
                    with: NSRange(location: match.range.location - 1, length: 1))
                if prev == "#" || prev == "&" { continue }
            }

            let windowStart = max(0, match.range.location - contextWindow)
            let windowLength = match.range.location - windowStart
            guard windowLength > 0 else { continue }
            let window = lowered.substring(
                with: NSRange(location: windowStart, length: windowLength))

            // The closest keyword inside the window wins.
            var keywordDistance: Int?
            for keyword in keywords {
                if let range = window.range(of: keyword, options: .backwards) {
                    let distance = window.distance(
                        from: range.upperBound, to: window.endIndex)
                    keywordDistance = min(keywordDistance ?? Int.max, distance)
                }
            }
            guard let distance = keywordDistance else { continue }

            var score = max(0, 80 - distance)
            switch code.count {
            case 6: score += 120          // the dominant OTP length
            case 4, 5, 7, 8: score += 40
            default: break
            }
            if score > bestScore {
                bestScore = score
                bestCode = code
            }
        }

        return bestCode
    }

    // MARK: - HTML → plain text

    private static func plainText(from html: String) -> String {
        var s = html

        // Drop invisible blocks entirely so their content cannot create
        // fake keyword/digit proximity.
        for tag in ["style", "script", "head", "noscript"] {
            s = s.replacingOccurrences(
                of: "<\\s*\(tag)\\b[\\s\\S]*?</\\s*\(tag)\\s*>",
                with: " ", options: [.regularExpression, .caseInsensitive])
        }
        // Common block separators become spaces.
        s = s.replacingOccurrences(
            of: "<\\s*(br|/p|/div|/td|/tr|/li|/h[1-6])[^>]*>",
            with: " ", options: [.regularExpression, .caseInsensitive])
        // Strip the remaining tags.
        s = s.replacingOccurrences(
            of: "<[^>]+>", with: " ", options: .regularExpression)

        // Decode the entities that can plausibly appear around codes.
        let namedEntities: [(String, String)] = [
            ("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&apos;", "'"), ("&#39;", "'"), ("&#160;", " ")
        ]
        for (entity, replacement) in namedEntities {
            s = s.replacingOccurrences(of: entity, with: replacement)
        }
        s = decodeNumericEntities(s)

        // Collapse whitespace runs: digits must stay standalone tokens.
        s = s.replacingOccurrences(
            of: "[\\s\\u00A0]+", with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeNumericEntities(_ input: String) -> String {
        guard input.contains("&#") else { return input }
        guard let regex = try? NSRegularExpression(pattern: "&#(\\d+);") else { return input }
        let ns = input as NSString
        var result = String()
        var cursor = 0
        for match in regex.matches(in: input, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let scalar = Int(ns.substring(with: match.range(at: 1))) ?? 0
            if let unicode = Unicode.Scalar(scalar), scalar > 32 {
                result.append(Character(unicode))
            } else {
                result.append(" ")
            }
            cursor = match.range.location + match.range.length
        }
        result += ns.substring(from: cursor)
        return result
    }

    private static func isYearLike(_ code: String) -> Bool {
        return code.count == 4 &&
            (code.hasPrefix("19") || code.hasPrefix("20"))
    }
}
