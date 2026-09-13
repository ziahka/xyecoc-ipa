import SwiftUI
import UIKit

struct AppIconPickerView: View {
    @ObservedObject private var iconManager = AppIconManager.shared

    var body: some View {
        Section("Иконка приложения") {
            ForEach(AppIconTheme.allCases) { theme in
                Button {
                    Haptics.selection()
                    Task {
                        await iconManager.setIconTheme(theme)
                    }
                } label: {
                    HStack(spacing: 14) {
                        iconThumbnail(for: theme)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(theme.displayName)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)

                            Text(theme.subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if iconManager.currentTheme == theme {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                                .font(.headline)
                        }
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if let error = iconManager.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func iconThumbnail(for theme: AppIconTheme) -> some View {
        if let image = loadThumbnail(for: theme) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1)
        } else {
            fallbackThumbnail(for: theme)
        }
    }

    private func loadThumbnail(for theme: AppIconTheme) -> UIImage? {
        let baseName = theme.iconName ?? "AppIcon"
        if let image = UIImage(named: baseName) {
            return image
        }
        if let path = Bundle.main.path(forResource: "\(baseName)@2x", ofType: "png") ??
                      Bundle.main.path(forResource: baseName, ofType: "png") {
            return UIImage(contentsOfFile: path)
        }
        return nil
    }

    @ViewBuilder
    private func fallbackThumbnail(for theme: AppIconTheme) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(fallbackBackground(for: theme))
                .frame(width: 44, height: 44)

            Image(systemName: "water.waves")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(fallbackSymbolColor(for: theme))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    private func fallbackBackground(for theme: AppIconTheme) -> LinearGradient {
        switch theme {
        case .standard:
            return LinearGradient(colors: [Color(red: 0.20, green: 0.60, blue: 1.0), Color.white], startPoint: .top, endPoint: .bottom)
        case .dark:
            return LinearGradient(colors: [Color(red: 0.11, green: 0.13, blue: 0.16), Color(red: 0.05, green: 0.06, blue: 0.07)], startPoint: .top, endPoint: .bottom)
        case .minimalist:
            return LinearGradient(colors: [Color(red: 0.98, green: 0.98, blue: 0.99), Color(red: 0.94, green: 0.94, blue: 0.96)], startPoint: .top, endPoint: .bottom)
        case .obsidian:
            return LinearGradient(colors: [Color(red: 0.04, green: 0.04, blue: 0.05), Color.black], startPoint: .top, endPoint: .bottom)
        case .cyberpunk:
            return LinearGradient(colors: [Color(red: 0.10, green: 0.04, blue: 0.18), Color(red: 0.03, green: 0.02, blue: 0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .sunset:
            return LinearGradient(colors: [Color(red: 0.15, green: 0.06, blue: 0.12), Color(red: 0.06, green: 0.02, blue: 0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .emerald:
            return LinearGradient(colors: [Color(red: 0.04, green: 0.12, blue: 0.08), Color(red: 0.02, green: 0.05, blue: 0.04)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .crimson:
            return LinearGradient(colors: [Color(red: 0.14, green: 0.04, blue: 0.07), Color(red: 0.05, green: 0.02, blue: 0.03)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .gold:
            return LinearGradient(colors: [Color(red: 0.12, green: 0.10, blue: 0.08), Color(red: 0.05, green: 0.04, blue: 0.03)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .aurora:
            return LinearGradient(colors: [Color(red: 0.10, green: 0.30, blue: 0.90), Color(red: 0.0, green: 0.82, blue: 0.63)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .candy:
            return LinearGradient(colors: [Color(red: 1.0, green: 0.25, blue: 0.47), Color(red: 1.0, green: 0.59, blue: 0.29)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private func fallbackSymbolColor(for theme: AppIconTheme) -> Color {
        switch theme {
        case .standard: return Color(red: 0.15, green: 0.55, blue: 1.0)
        case .dark: return Color(red: 0.25, green: 0.65, blue: 1.0)
        case .minimalist: return Color(red: 0.10, green: 0.10, blue: 0.12)
        case .obsidian: return Color.white
        case .cyberpunk: return Color(red: 1.0, green: 0.16, blue: 0.51)
        case .sunset: return Color(red: 1.0, green: 0.45, blue: 0.10)
        case .emerald: return Color(red: 0.0, green: 0.96, blue: 0.63)
        case .crimson: return Color(red: 1.0, green: 0.18, blue: 0.33)
        case .gold: return Color(red: 1.0, green: 0.85, blue: 0.40)
        case .aurora: return Color.white
        case .candy: return Color.white
        }
    }
}
