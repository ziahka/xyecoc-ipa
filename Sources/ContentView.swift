import SwiftUI

// MARK: - Auth state machine

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

    func reset() { state = .idle }

    func clearError() {
        if case .error = state { state = .idle }
    }
}

// MARK: - Root

struct ContentView: View {
    @StateObject private var accounts = AccountStore()
    @ObservedObject private var security = SecurityManager.shared
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("app_theme") private var selectedTheme: AppTheme = .cyan
    @AppStorage("app_language") private var selectedLanguage: AppLanguage = .ru

    var body: some View {
        ZStack {
            Group {
                if let active = accounts.activeEmail {
                    NavigationStack {
                        InboxView(accounts: accounts)
                    }
                    .id(active)
                } else {
                    LoginFlowView {
                        await accounts.onLoggedIn()
                    }
                }
            }
            .tint(selectedTheme.color)
            .environment(\.locale, Locale(identifier: selectedLanguage.rawValue))
            .task { await accounts.syncActiveCache() }

            if security.isLocked {
                LockOverlayView {
                    await accounts.logoutActive()
                }
                .transition(.opacity)
                .zIndex(999)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: security.isLocked)
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                security.lockAppIfNeeded()
                if security.isBiometryEnabled && security.isLocked {
                    security.authenticateWithBiometry()
                }
            }
        }
    }
}

// MARK: - Login flow wrapper

struct LoginFlowView: View {
    var onAuthenticated: () async -> Void
    @StateObject private var vm = AuthViewModel()

    var body: some View {
        Group {
            switch vm.state {
            case .requires2FA(let email, let password):
                TwoFactorView(vm: vm, email: email, password: password)
            default:
                LoginView(vm: vm)
            }
        }
        .animation(.easeInOut, value: vm.state)
        .onChange(of: vm.state) { newValue in
            if newValue == .success { Task { await onAuthenticated() } }
        }
    }
}

// MARK: - Login

struct LoginView: View {
    @ObservedObject var vm: AuthViewModel
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            VStack(spacing: 14) {
                Image(systemName: "envelope.circle.fill")
                    .resizable().scaledToFit().frame(width: 76, height: 76)
                    .foregroundStyle(Color.brand)
                Text("Xyecoc Mail").font(.largeTitle.bold())
                Text("Войдите в свой почтовый ящик")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                inputField(systemImage: "person", placeholder: "Имя ящика или email") {
                    TextField("Имя ящика или email", text: $email)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                }
                inputField(systemImage: "lock", placeholder: "Пароль") {
                    SecureField("Пароль", text: $password)
                        .textContentType(.password)
                }
            }

            if case .error(let message) = vm.state {
                Text(message).font(.footnote).foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }

            Button {
                vm.login(email: email, password: password)
            } label: {
                if vm.isLoading {
                    ProgressView().tint(.white).frame(maxWidth: .infinity)
                } else {
                    Text("Войти").bold().frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(vm.isLoading || email.isEmpty || password.isEmpty)

            Spacer(); Spacer()
        }
        .padding(28)
    }

    private func inputField<Content: View>(systemImage: String, placeholder: String,
                                           @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage).foregroundStyle(.secondary).frame(width: 22)
            content()
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Two-Factor

struct TwoFactorView: View {
    @ObservedObject var vm: AuthViewModel
    let email: String
    let password: String
    @State private var code = ""

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .resizable().scaledToFit().frame(width: 68, height: 68)
                .foregroundStyle(Color.brand)
            Text("Двухфакторная аутентификация")
                .font(.title2.bold()).multilineTextAlignment(.center)
            Text("Введите 6-значный код из приложения-аутентификатора для \(email)")
                .font(.footnote).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("000000", text: $code)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.title.monospaced())
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
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
                    ProgressView().tint(.white).frame(maxWidth: .infinity)
                } else {
                    Text("Подтвердить").bold().frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(vm.isLoading || code.count < 6)

            Button("Назад") { vm.reset() }
                .font(.footnote)

            Spacer(); Spacer()
        }
        .padding(28)
    }
}
