import Foundation

/// Локально закреплённые письма: всегда держатся сверху списка,
/// помечаются булавкой в строке. Идентификаторы писем сервера
/// уникальны, поэтому один набор хранится в UserDefaults.
/// Без изоляции актора: UserDefaults потокобезопасен, а хелпер зовётся
/// и из View (MainActor), и из не-isolated init MailRowState.
enum PinnedMailStore {
    private static let key = "pinned_mail_ids"

    static var all: Set<Int64> {
        Set((UserDefaults.standard.array(forKey: key) ?? [])
            .compactMap { ($0 as? NSNumber)?.int64Value })
    }

    static func isPinned(_ id: Int64) -> Bool {
        all.contains(id)
    }

    static func toggle(_ id: Int64) {
        var current = all
        if !current.insert(id).inserted {
            current.remove(id)
        }
        UserDefaults.standard.set(current.map(NSNumber.init(value:)), forKey: key)
    }
}
