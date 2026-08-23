//
//  Formatters.swift
//  XyecocMail
//
//  Port of Android `util/DateUtils.kt` plus a hex-color helper for tag badges.
//

import SwiftUI

enum DateUtils {

    private static let isoParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    private static let output: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "dd MMM, HH:mm"
        return f
    }()

    /// "2024-01-02T03:04:05.123" -> "02 Jan, 03:04"; falls back to the date part.
    static func formatDate(_ raw: String?) -> String {
        guard let raw = raw, !raw.isEmpty else { return "" }
        let trimmed = String(raw.split(separator: ".").first ?? Substring(raw))
        if let date = isoParser.date(from: trimmed) {
            return output.string(from: date)
        }
        return String(raw.split(separator: "T").first ?? Substring(raw))
    }

    /// Port of `formatFileSize`.
    static func formatFileSize(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024.0
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        return String(format: "%.1f MB", kb / 1024.0)
    }
}

extension Color {
    /// Parses "#RRGGBB" / "RRGGBB" / "#RRGGBBAA". Returns nil on malformed input.
    init?(hex: String?) {
        guard var s = hex?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else {
            return nil
        }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let value = UInt64(s, radix: 16) else {
            return nil
        }
        let r, g, b, a: Double
        if s.count == 6 {
            r = Double((value & 0xFF0000) >> 16) / 255
            g = Double((value & 0x00FF00) >> 8) / 255
            b = Double(value & 0x0000FF) / 255
            a = 1
        } else {
            r = Double((value & 0xFF000000) >> 24) / 255
            g = Double((value & 0x00FF0000) >> 16) / 255
            b = Double((value & 0x0000FF00) >> 8) / 255
            a = Double(value & 0x000000FF) / 255
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
