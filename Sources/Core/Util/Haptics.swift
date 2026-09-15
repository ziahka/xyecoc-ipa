//
//  Haptics.swift
//  XyecocMail
//

import UIKit

@MainActor
enum Haptics {
    private static let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private static let heavyGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private static let notificationGenerator = UINotificationFeedbackGenerator()

    /// Общий выключатель вибрации — настройка «haptics_enabled».
    private static var enabled: Bool { Prefs.hapticsEnabled }

    static func light() {
        guard enabled else { return }
        lightGenerator.prepare()
        lightGenerator.impactOccurred()
    }

    static func medium() {
        guard enabled else { return }
        mediumGenerator.prepare()
        mediumGenerator.impactOccurred()
    }

    static func heavy() {
        guard enabled else { return }
        heavyGenerator.prepare()
        heavyGenerator.impactOccurred()
    }

    static func success() {
        guard enabled else { return }
        notificationGenerator.prepare()
        notificationGenerator.notificationOccurred(.success)
    }

    static func warning() {
        guard enabled else { return }
        notificationGenerator.prepare()
        notificationGenerator.notificationOccurred(.warning)
    }

    static func error() {
        guard enabled else { return }
        notificationGenerator.prepare()
        notificationGenerator.notificationOccurred(.error)
    }
}