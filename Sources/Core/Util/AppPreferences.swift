import Foundation

// MARK: - Enum-значения настроек списка, отправки и поведения.
// Хранятся в UserDefaults по строковым rawValue; SwiftUI-вью подписываются
// через @AppStorage, не-вью код читает через Prefs.

enum ListDensity: String, CaseIterable, Identifiable {
    case compact, regular, spacious
    var id: String { rawValue }
    var title: String {
        switch self {
        case .compact: return "Компактно"
        case .regular: return "Обычно"
        case .spacious: return "Просторно"
        }
    }
}

enum RowPreview: String, CaseIterable, Identifiable {
    case full, oneLine, hidden
    var id: String { rawValue }
    var title: String {
        switch self {
        case .full: return "Две строки"
        case .oneLine: return "Одна строка"
        case .hidden: return "Скрыть"
        }
    }
}

enum SortOrder: String, CaseIterable, Identifiable {
    case newest, unreadFirst, oldest
    var id: String { rawValue }
    var title: String {
        switch self {
        case .newest: return "Новые сверху"
        case .unreadFirst: return "Непрочитанные сверху"
        case .oldest: return "Старые сверху"
        }
    }
}

enum SwipeActionKind: String, CaseIterable, Identifiable {
    case trash, delete, read, snooze, spam, copy
    var id: String { rawValue }
    var title: String {
        switch self {
        case .trash: return "В корзину"
        case .delete: return "Удалить навсегда"
        case .read: return "Прочитано"
        case .snooze: return "Отложить"
        case .spam: return "Спам"
        case .copy: return "Копировать email"
        }
    }
}

enum StartFolder: String, CaseIterable, Identifiable {
    case inbox, important, last
    var id: String { rawValue }
    var title: String {
        switch self {
        case .inbox: return "Входящие"
        case .important: return "Важные"
        case .last: return "Последняя открытая"
        }
    }
}

enum BadgeScope: String, CaseIterable, Identifiable {
    case inbox, all
    var id: String { rawValue }
    var title: String {
        switch self {
        case .inbox: return "Только входящие"
        case .all: return "Все папки"
        }
    }
}

enum PollInterval: String, CaseIterable, Identifiable {
    case s15, s30, s60, manual
    var id: String { rawValue }
    var title: String {
        switch self {
        case .s15: return "15 секунд"
        case .s30: return "30 секунд"
        case .s60: return "60 секунд"
        case .manual: return "Вручную"
        }
    }
    /// 0 = опрос выключен.
    var seconds: UInt64 {
        switch self {
        case .s15: return 15
        case .s30: return 30
        case .s60: return 60
        case .manual: return 0
        }
    }
}

enum UndoSendWindow: String, CaseIterable, Identifiable {
    case off, s3, s5, s10
    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: return "Выключена"
        case .s3: return "3 секунды"
        case .s5: return "5 секунд"
        case .s10: return "10 секунд"
        }
    }
    /// 0 = отправка сразу, без окна отмены.
    var seconds: Int {
        switch self {
        case .off: return 0
        case .s3: return 3
        case .s5: return 5
        case .s10: return 10
        }
    }
}

// MARK: - Type-safe читалка настроек для не-SwiftUI кода.

enum Prefs {
    private static func string(_ key: String) -> String? {
        UserDefaults.standard.string(forKey: key)
    }

    static var listDensity: ListDensity { ListDensity(rawValue: string("list_density") ?? "") ?? .regular }
    static var rowPreview: RowPreview { RowPreview(rawValue: string("row_preview") ?? "") ?? .full }
    static var sortOrder: SortOrder { SortOrder(rawValue: string("sort_order") ?? "") ?? .newest }
    static var swipeTrailing: SwipeActionKind { SwipeActionKind(rawValue: string("swipe_trailing") ?? "") ?? .trash }
    static var swipeLeading: SwipeActionKind { SwipeActionKind(rawValue: string("swipe_leading") ?? "") ?? .copy }
    static var startFolder: StartFolder { StartFolder(rawValue: string("start_folder") ?? "") ?? .inbox }
    static var badgeScope: BadgeScope { BadgeScope(rawValue: string("badge_scope") ?? "") ?? .inbox }
    static var pollInterval: PollInterval { PollInterval(rawValue: string("poll_interval") ?? "") ?? .s30 }
    static var undoSendWindow: UndoSendWindow { UndoSendWindow(rawValue: string("undo_send") ?? "") ?? .off }

    static var undoSeconds: Int { undoSendWindow.seconds }

    static var groupByDate: Bool {
        UserDefaults.standard.object(forKey: "group_by_date") as? Bool ?? false
    }
    static var privacySwitcher: Bool {
        UserDefaults.standard.object(forKey: "privacy_switcher") as? Bool ?? false
    }
    static var hapticsEnabled: Bool {
        UserDefaults.standard.object(forKey: "haptics_enabled") as? Bool ?? true
    }
    static var notifyNewMail: Bool {
        UserDefaults.standard.object(forKey: "notify_new_mail") as? Bool ?? true
    }
}
