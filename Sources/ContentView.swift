//
//  ContentView.swift
//  XyecocMail
//
//  Minimal but functional auth UI wired to `AuthRepository`, so you can test
//  authentication against the live backend (api.xyecoc.com) immediately.
//
//  Port of the relevant parts of `AuthViewModel` / `AuthScreens.kt`:
//   - login() normalizes bare usernames to "<name>@xyecoc.com"
//   - status == 2 branches to the 2FA screen (carrying email + password)
//   - status == 1 (or a token in `data`) is success
//

import SwiftUI

// MARK: - Auth state machine (mirrors Kotlin sealed class AuthUiState)

enum AuthState: Equatable {
    case idle
    case loading
    case success
    case messageSent
    case requires2FA(email: String, password: String)
    case error(String)
}

@MainActor
final class AuthViewModel: ObservableObject {

    @Published var state: AuthState = .idle

    private let repo = AuthRepository()

    var isLoading: Bool { state == .loading }

    func login(email: String, password: String) {
        let full = email.contains("@") ? email : "\(email)@xyecoc.com"
        state = .loading
        Task {
            let resp = await repo.login(email: full, password: password)
            switch resp.status {
            case 1:
                state = .success
            case 2:
                state = .requires2FA(email: full, password: password)
            default:
                if resp.isSuccess(), let t = resp.extractToken(), !t.isEmpty {
                    state = .success
                } else {
                    state = .error(resp.message ?? "Ошибка входа")
                }
            }
        }
    }

    func verify2fa(email: String, password: String, code: String) {
        state = .loading
        Task {
            let resp = await repo.verify2fa(email: email, password: password, secret: "", code: code)
            if resp.isSuccess() {
                state = .success
            } else {
                state = .error(resp.message ?? "Неверный код 2FA")
            }
        }
    }

    func logout() {
        repo.logout()
        Task { await MailDatabase.shared.clearAll() }
        state = .idle
    }

    /// Clear a transient error without leaving the current screen.
    func clearError() {
        if case .error = state { state = .idle }
    }
}

// MARK: - Root

struct ContentView: View {
    @StateObject private var vm = AuthViewModel()

    var body: some View {
        Group {
            switch vm.state {
            case .success:
                NavigationStack {
                    InboxView(onLogout: { vm.logout() })
                }
            case .requires2FA(let email, let password):
                TwoFactorView(vm: vm, email: email, password: password)
            default:
                LoginView(vm: vm)
            }
        }
        .animation(.default, value: vm.state)
        .onAppear {
            // Auto-advance if a valid token is already in the Keychain.
            if KeychainManager.shared.isLoggedIn { vm.state = .success }
        }
    }
}

// MARK: - Login

struct LoginView: View {
    @ObservedObject var vm: AuthViewModel
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "envelope.circle.fill")
                .resizable().scaledToFit().frame(width: 72, height: 72)
                .foregroundStyle(.tint)
            Text("Xyecoc Mail").font(.largeTitle.bold())

            VStack(spacing: 12) {
                TextField("Имя ящика или email", text: $email)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .padding().background(.thinMaterial).clipShape(RoundedRectangle(cornerRadius: 10))

                SecureField("Пароль", text: $password)
                    .textContentType(.password)
                    .padding().background(.thinMaterial).clipShape(RoundedRectangle(cornerRadius: 10))
            }

            if case .error(let message) = vm.state {
                Text(message).font(.footnote).foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                vm.login(email: email, password: password)
            } label: {
                if vm.isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Войти").bold().frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(vm.isLoading || email.isEmpty || password.isEmpty)

            Spacer()
        }
        .padding(24)
    }
}

// MARK: - Two-Factor

struct TwoFactorView: View {
    @ObservedObject var vm: AuthViewModel
    let email: String
    let password: String
    @State private var code = ""

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .resizable().scaledToFit().frame(width: 64, height: 64)
                .foregroundStyle(.tint)
            Text("Двухфакторная аутентификация").font(.title2.bold())
                .multilineTextAlignment(.center)
            Text("Введите 6-значный код из приложения-аутентификатора для \(email)")
                .font(.footnote).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("000000", text: $code)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.title.monospaced())
                .padding().background(.thinMaterial).clipShape(RoundedRectangle(cornerRadius: 10))
                .onChange(of: code) { newValue in
                    code = String(newValue.filter(\.isNumber).prefix(6))
                }

            if case .error(let message) = vm.state {
                Text(message).font(.footnote).foregroundStyle(.red)
            }

            Button {
                vm.verify2fa(email: email, password: password, code: code)
            } label: {
                if vm.isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Подтвердить").bold().frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(vm.isLoading || code.count < 6)

            Button("Назад") { vm.logout() }
                .font(.footnote)

            Spacer()
        }
        .padding(24)
    }
}

#Preview {
    ContentView()
}
