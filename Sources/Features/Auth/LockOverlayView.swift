import SwiftUI

struct LockOverlayView: View {
    @ObservedObject var security = SecurityManager.shared
    var onEmergencyReset: () async -> Void

    @State private var enteredPin: String = ""
    @State private var isError: Bool = false
    @State private var showResetAlert: Bool = false
    @FocusState private var isKeyboardFocused: Bool

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                VStack(spacing: 12) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(Color.accentColor)

                    Text("Введите PIN-код")
                        .font(.title2.bold())

                    Text("Для доступа к почте")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 18) {
                    ForEach(0..<4, id: \.self) { index in
                        Circle()
                            .fill(index < enteredPin.count ? Color.accentColor : Color.secondary.opacity(0.2))
                            .frame(width: 18, height: 18)
                            .scaleEffect(index < enteredPin.count ? 1.15 : 1.0)
                            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: enteredPin.count)
                    }
                }
                .padding(.vertical, 8)
                .offset(x: isError ? -10 : 0)

                TextField("", text: $enteredPin)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($isKeyboardFocused)
                    .frame(width: 1, height: 1)
                    .opacity(0.001)
                    .onChange(of: enteredPin) { newValue in
                        let filtered = String(newValue.filter(\.isNumber).prefix(4))
                        if filtered != enteredPin {
                            enteredPin = filtered
                        }
                        if enteredPin.count == 4 {
                            validatePin()
                        }
                    }

                Spacer()

                Button("Сбросить PIN через перелогин") {
                    showResetAlert = true
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.bottom, 24)
            }
            .padding(24)
        }
        .onAppear {
            isKeyboardFocused = true
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

    private func validatePin() {
        if security.verifyPin(enteredPin) {
            enteredPin = ""
        } else {
            withAnimation(.default.repeatCount(3, autoreverses: true).speed(4)) {
                isError = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isError = false
                enteredPin = ""
            }
        }
    }
}