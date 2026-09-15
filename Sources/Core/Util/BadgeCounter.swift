import Foundation
import UserNotifications

/// Установка счётчика бейджа на иконке приложения.
/// Современный API iOS 16+: у UIApplication.setApplicationIconBadgeNumber
/// нет члена в SDK iOS 18.2, а setBadgeCount не требует разрешений —
/// доступ к бейджу пользователь регулирует в системных настройках.
@MainActor
enum BadgeCounter {
    private static var lastRequested = -1

    static func set(_ count: Int) {
        // reload() зовёт это часто; одинаковые значения не отправляем.
        guard count != lastRequested else { return }
        lastRequested = count
        Task {
            try? await UNUserNotificationCenter.current().setBadgeCount(count)
        }
    }
}
