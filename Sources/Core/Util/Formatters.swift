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

    /// Parses the ISO-ish backend timestamps ("2024-01-02T03:04:05" with an
    /// optional ".fraction" part). Returns nil for empty/unparseable input.
    static func parseISO(_ raw: String?) -> Date? {
        guard let raw = raw, !raw.isEmpty else { return nil }
        let trimmed = String(raw.split(separator: ".").first ?? Substring(raw))
        return isoParser.date(from: trimmed)
    }

    // Compact list formatting: "14:05" today, "Вчера", "05 мар" this year,
    // "05 мар 2023" for older years. Falls back to formatDate.
    private static let timeOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let dayMonthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "dd MMM"
        return f
    }()

    private static let dayMonthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "dd MMM yyyy"
        return f
    }()

    private static let yesterdayWord = NSLocalizedString("Вчера", comment: "List row date for yesterday")

    static func formatDateRelative(_ raw: String?) -> String {
        guard let date = parseISO(raw) else { return formatDate(raw) }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return timeOnlyFormatter.string(from: date)
        }
        if calendar.isDateInYesterday(date) {
            return yesterdayWord
        }
        let yearDelta = calendar.dateComponents([.year], from: date, to: Date()).year ?? 0
        if yearDelta >= 1 {
            return dayMonthYearFormatter.string(from: date)
        }
        return dayMonthFormatter.string(from: date)
    }

    /// Label for a snooze deadline: "до 20:00" today, "до 12 сен, 09:00" otherwise.
    static func snoozeLabel(until date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "до " + timeOnlyFormatter.string(from: date)
        }
        return "до " + dayMonthFormatter.string(from: date) + ", " + timeOnlyFormatter.string(from: date)
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

enum AppAppearance: String, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Системная"
        case .light: return "Светлая"
        case .dark: return "Тёмная"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case ru = "ru"
    case en = "en"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ru: return "Русский"
        case .en: return "English"
        }
    }

    var locale: Locale {
        Locale(identifier: rawValue)
    }

    static var currentCode: String {
        UserDefaults.standard.string(forKey: "app_language") ?? "ru"
    }
}

/// Reading font size for the mail reader WebView ("mail_font_size" setting).
enum MailFontSize: String, CaseIterable, Identifiable {
    case small = "small"
    case medium = "medium"
    case large = "large"
    case extraLarge = "extra_large"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: return "Мелкий"
        case .medium: return "Обычный"
        case .large: return "Крупный"
        case .extraLarge: return "Очень крупный"
        }
    }

    /// Base body font-size in CSS points used by the reader HTML template.
    var points: Int {
        switch self {
        case .small: return 14
        case .medium: return 16
        case .large: return 19
        case .extraLarge: return 23
        }
    }
}

// MARK: - Snooze presets

/// Presets for the local "отложить письмо" feature. The mail stays cached in
/// its own folder but is hidden from lists until the wake-up moment.
enum SnoozePreset: CaseIterable, Identifiable {
    case oneHour
    case threeHours
    case thisEvening
    case tomorrowMorning
    case nextWeek

    var id: Self { self }

    var title: String {
        switch self {
        case .oneHour: return "На час"
        case .threeHours: return "На 3 часа"
        case .thisEvening: return "Вечером (20:00)"
        case .tomorrowMorning: return "Завтра утром (9:00)"
        case .nextWeek: return "На неделю"
        }
    }

    var systemImage: String {
        switch self {
        case .oneHour: return "clock"
        case .threeHours: return "alarm"
        case .thisEvening: return "sunset.fill"
        case .tomorrowMorning: return "sunrise.fill"
        case .nextWeek: return "calendar.badge.clock"
        }
    }

    /// Wake-up date computed from the given moment.
    func date(from now: Date = Date(), calendar: Calendar = .current) -> Date {
        switch self {
        case .oneHour:
            return now.addingTimeInterval(3600)
        case .threeHours:
            return now.addingTimeInterval(3 * 3600)
        case .thisEvening:
            let day = calendar.dateComponents([.year, .month, .day], from: now)
            var evening = calendar.date(from: DateComponents(
                year: day.year, month: day.month, day: day.day, hour: 20))
                ?? now.addingTimeInterval(4 * 3600)
            if evening <= now {
                evening = evening.addingTimeInterval(86400)
            }
            return evening
        case .tomorrowMorning:
            let base = calendar.startOfDay(for: now)
            return calendar.date(byAdding: DateComponents(day: 1, hour: 9), to: base)
                ?? now.addingTimeInterval(86400 + 3600)
        case .nextWeek:
            return now.addingTimeInterval(7 * 86400)
        }
    }
}