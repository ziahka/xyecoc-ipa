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
    /// Xyecoc brand palette (from the official logo).
    static let brand = Color(hex: "#18C9E1") ?? .accentColor
    static let brandLight = Color(hex: "#9AEDF9") ?? .accentColor

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

enum AppTheme: String, CaseIterable, Identifiable {
    case cyan = "cyan"
    case ocean = "ocean"
    case indigo = "indigo"
    case lavender = "lavender"
    case mint = "mint"
    case emerald = "emerald"
    case peach = "peach"
    case terracotta = "terracotta"
    case rose = "rose"
    case slate = "slate"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cyan: return "Морская волна"
        case .ocean: return "Океан"
        case .indigo: return "Индиго"
        case .lavender: return "Лаванда"
        case .mint: return "Мята"
        case .emerald: return "Изумруд"
        case .peach: return "Персик"
        case .terracotta: return "Терракота"
        case .rose: return "Пудра"
        case .slate: return "Графит"
        }
    }

    var color: Color {
        switch self {
        case .cyan: return Color(hex: "#18C9E1") ?? .cyan
        case .ocean: return Color(hex: "#3B82F6") ?? .blue
        case .indigo: return Color(hex: "#6366F1") ?? .indigo
        case .lavender: return Color(hex: "#8B5CF6") ?? .purple
        case .mint: return Color(hex: "#10B981") ?? .mint
        case .emerald: return Color(hex: "#059669") ?? .green
        case .peach: return Color(hex: "#F59E0B") ?? .orange
        case .terracotta: return Color(hex: "#EA580C") ?? .orange
        case .rose: return Color(hex: "#EC4899") ?? .pink
        case .slate: return Color(hex: "#64748B") ?? .gray
        }
    }

    var backgroundColor: Color {
        switch self {
        case .cyan: return Color(hex: "#E0F7FA") ?? .cyan.opacity(0.12)
        case .ocean: return Color(hex: "#EFF6FF") ?? .blue.opacity(0.12)
        case .indigo: return Color(hex: "#EEF2FF") ?? .indigo.opacity(0.12)
        case .lavender: return Color(hex: "#F5F3FF") ?? .purple.opacity(0.12)
        case .mint: return Color(hex: "#ECFDF5") ?? .mint.opacity(0.12)
        case .emerald: return Color(hex: "#E6F4EA") ?? .green.opacity(0.12)
        case .peach: return Color(hex: "#FFFBEB") ?? .orange.opacity(0.12)
        case .terracotta: return Color(hex: "#FFF7ED") ?? .orange.opacity(0.12)
        case .rose: return Color(hex: "#FDF2F8") ?? .pink.opacity(0.12)
        case .slate: return Color(hex: "#F1F5F9") ?? .gray.opacity(0.12)
        }
    }
}