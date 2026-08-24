//
//  SettingsView.swift
//  XyecocMail
//
//  Application settings view.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("app_theme") private var selectedTheme: AppTheme = .cyan
    @AppStorage("app_language") private var selectedLanguage: AppLanguage = .ru

    var body: some View {
        List {
            Section("Язык / Language") {
                Picker("Язык интерфейса", selection: $selectedLanguage) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.title).tag(lang)
                    }
                }
            }

            Section("Внешний вид") {
                Picker("Цвет акцента", selection: $selectedTheme) {
                    ForEach(AppTheme.allCases) { theme in
                        HStack {
                            Circle()
                                .fill(theme.color)
                                .frame(width: 14, height: 14)
                            Text(theme.title)
                        }
                        .tag(theme)
                    }
                }
            }
        }
        .navigationTitle("Настройки")
    }
}
#Preview {
    NavigationStack {
        SettingsView()
    }
}