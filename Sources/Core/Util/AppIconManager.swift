import UIKit
import Combine

enum AppIconTheme: String, CaseIterable, Identifiable {
    case standard = "Default"
    case dark = "AppIcon-Dark"
    case minimalist = "AppIcon-Minimalist"
    case obsidian = "AppIcon-Obsidian"
    case cyberpunk = "AppIcon-Cyberpunk"
    case sunset = "AppIcon-Sunset"
    case emerald = "AppIcon-Emerald"
    case crimson = "AppIcon-Crimson"
    case gold = "AppIcon-Gold"
    case aurora = "AppIcon-Aurora"
    case candy = "AppIcon-Candy"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: return "По умолчанию"
        case .dark: return "Midnight OLED"
        case .minimalist: return "Белый монохром"
        case .obsidian: return "Обсидиан"
        case .cyberpunk: return "Киберпанк"
        case .sunset: return "Закат (Sunset)"
        case .emerald: return "Изумруд (Emerald)"
        case .crimson: return "Рубин (Crimson)"
        case .gold: return "Золото (Gold)"
        case .aurora: return "Аврора (Aurora)"
        case .candy: return "Карамель (Candy)"
        }
    }

    var subtitle: String {
        switch self {
        case .standard: return "Оригинальная иконка приложения"
        case .dark: return "Тёмный графит и неоновый синий"
        case .minimalist: return "Белоснежный фон и чёрный логотип"
        case .obsidian: return "Глубокий чёрный и белый логотип"
        case .cyberpunk: return "Неоновый пурпур и электрик-циан"
        case .sunset: return "Тёплый закатный коралл и амбра"
        case .emerald: return "Тёмный лес и яркая мята"
        case .crimson: return "Винный фон и пламенный рубин"
        case .gold: return "Титан и благородное золото"
        case .aurora: return "Градиент северного сияния"
        case .candy: return "Яркий персиково-малиновый градиент"
        }
    }

    var iconName: String? {
        switch self {
        case .standard: return nil
        case .dark: return "AppIcon-Dark"
        case .minimalist: return "AppIcon-Minimalist"
        case .obsidian: return "AppIcon-Obsidian"
        case .cyberpunk: return "AppIcon-Cyberpunk"
        case .sunset: return "AppIcon-Sunset"
        case .emerald: return "AppIcon-Emerald"
        case .crimson: return "AppIcon-Crimson"
        case .gold: return "AppIcon-Gold"
        case .aurora: return "AppIcon-Aurora"
        case .candy: return "AppIcon-Candy"
        }
    }
}

@MainActor
final class AppIconManager: ObservableObject {
    static let shared = AppIconManager()

    @Published private(set) var currentTheme: AppIconTheme = .standard
    @Published var lastError: String?

    private init() {
        syncCurrentTheme()
    }

    func syncCurrentTheme() {
        guard UIApplication.shared.supportsAlternateIcons else {
            currentTheme = .standard
            return
        }

        if let alternate = UIApplication.shared.alternateIconName {
            currentTheme = AppIconTheme(rawValue: alternate) ?? .standard
        } else {
            currentTheme = .standard
        }
    }

    func setIconTheme(_ theme: AppIconTheme) async {
        guard UIApplication.shared.supportsAlternateIcons else {
            lastError = "Смена иконки не поддерживается на данном устройстве."
            return
        }

        guard theme != currentTheme else { return }

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                UIApplication.shared.setAlternateIconName(theme.iconName) { error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
            self.currentTheme = theme
            self.lastError = nil
        } catch {
            self.lastError = error.localizedDescription
        }
    }
}
