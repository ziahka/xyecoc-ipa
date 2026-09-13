import UIKit
import Combine

enum AppIconTheme: String, CaseIterable, Identifiable {
    case standard = "Default"
    case dark = "AppIcon-Dark"
    case minimalist = "AppIcon-Minimalist"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: return "Стандартная (Морская волна)"
        case .dark: return "Тёмная (Midnight)"
        case .minimalist: return "Минимализм (Монохром)"
        }
    }

    var iconName: String? {
        switch self {
        case .standard: return nil
        case .dark: return "AppIcon-Dark"
        case .minimalist: return "AppIcon-Minimalist"
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
