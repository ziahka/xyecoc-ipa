import SwiftUI

struct LockOverlayView: View {
    @ObservedObject var security = SecurityManager.shared
    var onEmergencyReset: () async -> Void

    @State private var enteredPin: String = ""
    @State private var shakeOffset: CGFloat = 0
    @State private var showResetAlert: Bool = false

    private let columns: [GridItem] = [
        GridItem(.fixed(76), spacing: 24),
        GridItem(.fixed(76), spacing: 24),
        GridItem(.fixed(76), spacing: 24)
    ]

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 20)

                VStack(spacing: 12) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(Color.accentColor)

                    Text("Введите PIN-код")
                        .font(.title2.bold())

                    Text("Для доступа к почте")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 20)

                // PIN indicator dots
                HStack(spacing: 18) {
                    ForEach(0..<4, id: \.self) { index in
                        Circle()
                            .fill(index < enteredPin.count ? Color.accentColor : Color.secondary.opacity(0.25))
                            .frame(width: 16, height: 16)
                            .scaleEffect(index < enteredPin.count ? 1.15 : 1.0)
                            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: enteredPin.count)
                    }
                }
                .padding(.vertical, 12)
                .offset(x: shakeOffset)

                Spacer(minLength: 24)

                // Keypad grid
                VStack(spacing: 16) {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(1...9, id: \.self) { digit in
                            KeypadButton(title: "\(digit)", systemImage: nil) {
                                handleDigit("\(digit)")
                            }
                        }

                        // Bottom row
                        if security.isBiometricsAvailable {
                            KeypadButton(title: nil, systemImage: security.biometricIconName) {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                Task {
                                    _ = await security.authenticateWithBiometrics()
                                }
                            }
                        } else {
                            Color.clear
                                .frame(width: 76, height: 76)
                        }

                        KeypadButton(title: "0", systemImage: nil) {
                            handleDigit("0")
                        }

                        KeypadButton(title: nil, systemImage: "delete.left.fill") {
                            handleBackspace()
                        }
                    }
                }

                Spacer(minLength: 28)

                Button("Сбросить PIN через перелогин") {
                    showResetAlert = true
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 24)
        }
        .task {
            if security.isBiometricsAvailable {
                _ = await security.authenticateWithBiometrics()
            }
        }
        .alert("Сброс PIN-кода", isPresented: $showResetAlert) {
            Button("Отмена", role: .cancel) { }
            Button("Сбросить и выйти", role: .destructive) {
                security.emergencyReset()
                Task {
                    await onEmergencyReset()
                }
            }
        } message: {
            Text("PIN-код будет удален. Потребуется повторно войти в почтовый аккаунт.")
        }
    }

    private func handleDigit(_ digit: String) {
        guard enteredPin.count < 4 else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        enteredPin.append(digit)
        if enteredPin.count == 4 {
            validatePin()
        }
    }

    private func handleBackspace() {
        guard !enteredPin.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        enteredPin.removeLast()
    }

    private func validatePin() {
        if security.verifyPin(enteredPin) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            enteredPin = ""
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            withAnimation(.easeInOut(duration: 0.08).repeatCount(4, autoreverses: true)) {
                shakeOffset = 12
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                shakeOffset = 0
                enteredPin = ""
            }
        }
    }
}

private struct KeypadButton: View {
    let title: String?
    let systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 76, height: 76)

                if let title = title {
                    Text(title)
                        .font(.system(size: 30, weight: .regular, design: .rounded))
                        .foregroundStyle(Color.primary)
                } else if let systemImage = systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color.primary)
                }
            }
        }
        .buttonStyle(KeypadButtonStyle())
    }
}

private struct KeypadButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}