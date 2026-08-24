import SwiftUI

struct SettingsView: View {
    @AppStorage("app_theme") private var selectedTheme: AppTheme = .cyan
    @AppStorage("app_language") private var selectedLanguage: AppLanguage = .ru

    @ObservedObject private var security = SecurityManager.shared
    @State private var showSetPinSheet = false
    @State private var newPin = ""
    @State private var confirmPin = ""
    @State private var pinStep = 0
    @State private var pinError: String?

    var body: some View {
        List {
            Section("Безопасность") {
                if security.hasPin {
                    Button("Изменить PIN-код") {
                        resetPinFlow()
                        showSetPinSheet = true
                    }

                    Button(role: .destructive) {
                        security.removePin()
                    } label: {
                        Text("Удалить PIN-код")
                    }

                    Toggle("Использовать \(security.biometryTitle)", isOn: $security.isBiometryEnabled)
                } else {
                    Button("Установить PIN-код") {
                        resetPinFlow()
                        showSetPinSheet = true
                    }
                }
            }

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
        .sheet(isPresented: $showSetPinSheet) {
            pinSetupSheet
        }
    }

    private var pinSetupSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text(pinStep == 0 ? "Придумайте 4-значный PIN" : "Повторите 4-значный PIN")
                    .font(.headline)
                    .padding(.top, 24)

                SecureField("0000", text: pinStep == 0 ? $newPin : $confirmPin)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.title.monospaced())
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 32)
                    .onChange(of: pinStep == 0 ? newPin : confirmPin) { newValue in
                        let filtered = String(newValue.filter(\.isNumber).prefix(4))
                        if pinStep == 0 {
                            newPin = filtered
                            if newPin.count == 4 {
                                pinStep = 1
                            }
                        } else {
                            confirmPin = filtered
                            if confirmPin.count == 4 {
                                if newPin == confirmPin {
                                    _ = security.setPin(newPin)
                                    showSetPinSheet = false
                                } else {
                                    pinError = "Коды не совпадают"
                                    confirmPin = ""
                                }
                            }
                        }
                    }

                if let err = pinError {
                    Text(err)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Spacer()
            }
            .navigationTitle("Установка PIN-кода")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { showSetPinSheet = false }
                }
            }
        }
    }

    private func resetPinFlow() {
        newPin = ""
        confirmPin = ""
        pinStep = 0
        pinError = nil
    }
}
