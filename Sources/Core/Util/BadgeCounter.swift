import Foundation
import UserNotifications

/// Установка счётчика бейджа на иконке приложения.
/// Современный API iOS 16+: у UIApplication.setApplicationIconBadgeNumber
/// нет члена в SDK iOS 18.2, а setBadgeCount не требует разрешений —
/// доступ к бейджу пользователь регулирует в системных настройках.
@MainActor
enum BadgeCounter {
    static func set(_ count: Int) {
        Task {
            try? await UNUserNotificationCenter.current().setBadgeCount(count)
        }
    }
}
