import SwiftUI

struct AppIconPickerView: View {
    @ObservedObject private var iconManager = AppIconManager.shared

    var body: some View {
        Section("Иконка приложения") {
            ForEach(AppIconTheme.allCases) { theme in
                Button {
                    Haptics.light()
                    Task {
                        await iconManager.setIconTheme(theme)
                    }
                } label: {
                    HStack(spacing: 14) {
                        iconThumbnail(for: theme)

                        Text(theme.displayName)
                            .font(.subheadline)
                            .foregroundStyle(.primary)

                        Spacer()

                        if iconManager.currentTheme == theme {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                                .font(.headline)
                        }
                    }
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
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(thumbnailBackground(for: theme))
                .frame(width: 38, height: 38)

            Image(systemName: "envelope.fill")
                .font(.system(size: 16))
                .foregroundStyle(thumbnailSymbolColor(for: theme))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        )
    }

    private func thumbnailBackground(for theme: AppIconTheme) -> Color {
        switch theme {
        case .standard: return Color(red: 0.09, green: 0.79, blue: 0.88)
        case .dark: return Color(red: 0.10, green: 0.10, blue: 0.12)
        case .minimalist: return Color.white
        }
    }

    private func thumbnailSymbolColor(for theme: AppIconTheme) -> Color {
        switch theme {
        case .standard: return .white
        case .dark: return Color(red: 0.09, green: 0.79, blue: 0.88)
        case .minimalist: return .black
        }
    }
}
