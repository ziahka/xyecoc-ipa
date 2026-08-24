//
//  SettingsView.swift
//  XyecocMail
//
//  Application settings view.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("app_theme") private var selectedTheme: AppTheme = .cyan

    var body: some View {
        List {
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