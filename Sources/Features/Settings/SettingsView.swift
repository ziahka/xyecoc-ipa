//
//  SettingsView.swift
//  XyecocMail
//

import SwiftUI

// MARK: - ViewModel

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var email: String = ""
    @Published var reserveEmail: String = ""
    @Published var signatureReply: String = ""
    @Published var signatureNew: String = ""
    @Published var is2FAEnabled: Bool = false
    @Published var aliases: [AliasAddress] = []
    @Published var folders: [Folder] = []
    @Published var tags: [Tag] = []
    @Published var isLoading: Bool = false

    private let repo = SettingsRepository()
    private let db = MailDatabase.shared

    func load() async {
        isLoading = true
        defer { isLoading = false }

        email = KeychainManager.shared.activeEmail() ?? ""
        let resp = await repo.getProfile()
        if resp.isSuccess() {
            if let em = resp.email, !em.isEmpty { self.email = em }
            self.reserveEmail = resp.reserveEmail ?? ""
            self.signatureReply = resp.signature ?? ""
            self.signatureNew = resp.signature ?? ""
            self.is2FAEnabled = (resp.twoFactor == "1" || resp.twoFactor == "true")
        }

        let aliasResp = await repo.fetchAddresses()
        if let list = aliasResp.addresses {
            self.aliases = list
        }

        self.folders = await db.folders()
        self.tags = await db.tags()
    }

    func updatePassword(old: String, new: String) async -> Bool {
        let resp = await repo.updatePassword(old: old, new: new)
        return resp.isSuccess()
    }

    func updateReserveEmail(password: String, newEmail: String) async -> Bool {
        let resp = await repo.updateReserveEmail(password: password, reserveEmail: newEmail)
        if resp.isSuccess() {
            self.reserveEmail = newEmail
            return true
        }
        return false
    }

    func disable2FA(password: String) async -> Bool {
        let resp = await repo.disable2FA(password: password)
        if resp.isSuccess() {
            self.is2FAEnabled = false
            return true
        }
        return false
    }

    func saveSignatures() async -> Bool {
        let resp = await repo.updateSignatures(reply: signatureReply, new: signatureNew)
        return resp.isSuccess()
    }

    func deleteAlias(_ address: String) async {
        let resp = await repo.deleteAlias(email: address)
        if resp.isSuccess() {
            aliases.removeAll { $0.email == address }
        }
    }

    func createFolder(_ name: String) async -> Bool {
        let resp = await repo.createFolder(name: name)
        if resp.isSuccess() {
            folders = await db.folders()
            return true
        }
        return false
    }

    func deleteFolder(_ name: String) async {
        let resp = await repo.deleteFolder(name: name)
        if resp.isSuccess() {
            folders = await db.folders()
        }
    }

    func createTag(name: String, colorHex: String) async -> Bool {
        let resp = await repo.createTag(name: name, colorHex: colorHex)
        if resp.isSuccess() {
            tags = await db.tags()
            return true
        }
        return false
    }

    func deleteTag(id: Int64) async {
        let resp = await repo.deleteTag(id: id)
        if resp.isSuccess() {
            tags = await db.tags()
        }
    }

    func deleteAccount(password: String) async -> Bool {
        let resp = await repo.deleteAccount(password: password)
        return resp.isSuccess()
    }
}

// MARK: - Root Settings Screen

struct SettingsView: View {
    @ObservedObject var accounts: AccountStore
    @StateObject private var vm = SettingsViewModel()
    @ObservedObject private var security = SecurityManager.shared

    @AppStorage("app_theme") private var selectedTheme: AppTheme = .cyan[cite: 1, 3]
    @AppStorage("app_language") private var selectedLanguage: AppLanguage = .ru[cite: 3, 4]

    // Sheets & Dialogs
    @State private var showPasswordSheet = false
    @State private var showReserveSheet = false
    @State private var show2FASheet = false
    @State private var showSetPinSheet = false
    @State private var showFeedbackSheet = false
    @State private var showDeleteAlert = false
    @State private var deletePassword = ""

    // PIN Setup State
    @State private var newPin = ""
    @State private var confirmPin = ""
    @State private var pinStep = 0
    @State private var pinError: String?

    var body: some View {
        List {
            accountSection
            appearanceAndLangSection
            securitySection
            mailManagementSection
            appAndDestructiveSection
        }
        .navigationTitle("Настройки")[cite: 3, 4]
        .task { await vm.load() }
        .sheet(isPresented: $showPasswordSheet) { ChangePasswordSheet(vm: vm) }
        .sheet(isPresented: $showReserveSheet) { ReserveEmailSheet(vm: vm) }
        .sheet(isPresented: $show2FASheet) { TwoFactorSetupSheet(vm: vm) }
        .sheet(isPresented: $showFeedbackSheet) { FeedbackSheet() }
        .sheet(isPresented: $showSetPinSheet) { pinSetupSheet }
        .alert("Удаление аккаунта", isPresented: $showDeleteAlert) {
            SecureField("Пароль от ящика", text: $deletePassword)
            Button("Отмена", role: .cancel) { deletePassword = "" }
            Button("Удалить навсегда", role: .destructive) {
                Task {
                    if await vm.deleteAccount(password: deletePassword) {
                        await accounts.logoutActive()
                    }
                    deletePassword = ""
                }
            }
        } message: {
            Text("Это действие безвозвратно удалит почтовый ящик и всю корреспонденцию.")
        }
    }

    // MARK: - 1. Секция «Аккаунт»

    private var accountSection: some View {
        Section("Аккаунт") {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(AvatarGenerator.backgroundColor(for: vm.email))[cite: 5]
                        .frame(width: 44, height: 44)
                    Text(AvatarGenerator.initials(displayName: vm.email, email: vm.email))[cite: 5]
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.email.isEmpty ? "Загрузка..." : vm.email)
                        .font(.subheadline.weight(.semibold))
                    Text("Основной адрес")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)

            Button {
                showPasswordSheet = true
            } label: {
                Label("Изменить пароль", systemImage: "key")
            }

            Button {
                show2FASheet = true
            } label: {
                HStack {
                    Label("Двухфакторная аутентификация (2FA)", systemImage: "lock.shield")
                    Spacer()
                    Text(vm.is2FAEnabled ? "Вкл" : "Выкл")
                        .font(.footnote)
                        .foregroundStyle(vm.is2FAEnabled ? .green : .secondary)
                }
            }

            Button {
                showReserveSheet = true
            } label: {
                HStack {
                    Label("Резервный email", systemImage: "envelope.badge.shield.half.filled")
                    Spacer()
                    Text(vm.reserveEmail.isEmpty ? "Не указан" : vm.reserveEmail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - 2. Секция «Внешний вид и локализация»

    private var appearanceAndLangSection: some View {
        Section("Внешний вид и локализация") {
            Picker("Цвет темы", selection: $selectedTheme) {
                ForEach(AppTheme.allCases) { theme in
                    HStack {
                        Circle().fill(theme.color).frame(width: 14, height: 14)[cite: 1, 3]
                        Text(theme.title)[cite: 1, 3]
                    }
                    .tag(theme)[cite: 1, 3]
                }
            }

            Picker("Язык интерфейса", selection: $selectedLanguage) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.title).tag(lang)[cite: 3, 4]
                }
            }
        }
    }

    // MARK: - 3. Секция «Безопасность»

    private var securitySection: some View {
        Section("Безопасность устройства") {
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
    }

    // MARK: - 4. Секция «Почта»

    private var mailManagementSection: some View {
        Section("Почта") {
            NavigationLink {
                SignaturesEditorView(vm: vm)
            } label: {
                Label("Подписи писем", systemImage: "signature")
            }

            NavigationLink {
                AliasesManagerView(vm: vm)
            } label: {
                HStack {
                    Label("Псевдонимы (алиасы)", systemImage: "person.2")
                    Spacer()
                    Text("\(vm.aliases.count)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            NavigationLink {
                FoldersAndTagsView(vm: vm)
            } label: {
                Label("Папки и теги", systemImage: "folder.badge.gearshape")
            }
        }
    }

    // MARK: - 5. Секция «О приложении и аккаунте»

    private var appAndDestructiveSection: some View {
        Section("О приложении") {
            Button {
                showFeedbackSheet = true
            } label: {
                Label("Служба поддержки / Отзыв", systemImage: "bubble.left.and.exclamationmark.bubble.right")
            }

            HStack {
                Text("Версия клиента")
                Spacer()
                Text("1.0.0 (Milestone 5)")
                    .foregroundStyle(.secondary)
            }

            Button(role: .destructive) {
                Task { await accounts.logoutActive() }
            } label: {
                Label("Выйти из аккаунта", systemImage: "rectangle.portrait.and.arrow.right")
            }

            Button(role: .destructive) {
                showDeleteAlert = true
            } label: {
                Label("Удалить аккаунт", systemImage: "trash.fill")
            }
        }
    }

    // MARK: - PIN Setup Flow

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
                            if newPin.count == 4 { pinStep = 1 }
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

// MARK: - Sheets & Views

struct ChangePasswordSheet: View {
    @ObservedObject var vm: SettingsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Текущий пароль", text: $oldPassword)
                    SecureField("Новый пароль", text: $newPassword)
                    SecureField("Повторите пароль", text: $confirmPassword)
                }

                if let err = errorMessage {
                    Section {
                        Text(err).foregroundStyle(.red).font(.footnote)
                    }
                }

                Section {
                    Button(isSubmitting ? "Сохранение..." : "Изменить пароль") {
                        guard newPassword == confirmPassword else {
                            errorMessage = "Пароли не совпадают"
                            return
                        }
                        isSubmitting = true
                        Task {
                            if await vm.updatePassword(old: oldPassword, new: newPassword) {
                                dismiss()
                            } else {
                                errorMessage = "Неверный текущий пароль или ошибка сервера"
                            }
                            isSubmitting = false
                        }
                    }
                    .disabled(oldPassword.isEmpty || newPassword.isEmpty || isSubmitting)
                }
            }
            .navigationTitle("Смена пароля")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
            }
        }
    }
}

struct ReserveEmailSheet: View {
    @ObservedObject var vm: SettingsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Резервный почтовый ящик") {
                    TextField("example@domain.com", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                    SecureField("Пароль от аккаунта", text: $password)
                }

                if let err = errorMessage {
                    Text(err).foregroundStyle(.red).font(.footnote)
                }

                Button(isSubmitting ? "Сохранение..." : "Сохранить") {
                    isSubmitting = true
                    Task {
                        if await vm.updateReserveEmail(password: password, newEmail: email) {
                            dismiss()
                        } else {
                            errorMessage = "Ошибка обновления. Проверьте пароль."
                        }
                        isSubmitting = false
                    }
                }
                .disabled(email.isEmpty || password.isEmpty || isSubmitting)
            }
            .navigationTitle("Резервный Email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
            }
            .onAppear { email = vm.reserveEmail }
        }
    }
}

struct TwoFactorSetupSheet: View {
    @ObservedObject var vm: SettingsViewModel
    @Environment(\.dismiss) private var dismiss
    private let repo = SettingsRepository()

    @State private var qrData: TwoFactorQrData?
    @State private var code = ""
    @State private var password = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if vm.is2FAEnabled {
                    Section("Отключение двухфакторной защиты") {
                        SecureField("Пароль от аккаунта", text: $password)
                        Button("Отключить 2FA", role: .destructive) {
                            Task {
                                if await vm.disable2FA(password: password) {
                                    dismiss()
                                } else {
                                    errorMessage = "Неверный пароль"
                                }
                            }
                        }
                        .disabled(password.isEmpty)
                    }
                } else {
                    Section("Настройка 2FA") {
                        if let qr = qrData {
                            Text("Секретный ключ: \(qr.secret)")
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                            TextField("6-значный код TOTP", text: $code)
                                .keyboardType(.numberPad)
                            Button("Активировать") {
                                Task {
                                    let resp = await repo.enable2FA(code: code, secret: qr.secret)
                                    if resp.isSuccess() {
                                        vm.is2FAEnabled = true
                                        dismiss()
                                    } else {
                                        errorMessage = resp.message ?? "Неверный код"
                                    }
                                }
                            }
                            .disabled(code.count != 6)
                        } else {
                            ProgressView("Генерация параметров 2FA...")
                        }
                    }
                }

                if let err = errorMessage {
                    Text(err).foregroundStyle(.red).font(.footnote)
                }
            }
            .navigationTitle("2FA Безопасность")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
            }
            .task {
                if !vm.is2FAEnabled {
                    let resp = await repo.get2FAQR()
                    if let data = resp.twoFactorQrData() {
                        self.qrData = data
                    }
                }
            }
        }
    }
}

struct SignaturesEditorView: View {
    @ObservedObject var vm: SettingsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isSaved = false

    var body: some View {
        Form {
            Section("Подпись для новых сообщений") {
                TextEditor(text: $vm.signatureNew)
                    .frame(minHeight: 80)
            }
            Section("Подпись для ответов на письма") {
                TextEditor(text: $vm.signatureReply)
                    .frame(minHeight: 80)
            }
            Section {
                Button("Сохранить изменения") {
                    Task {
                        _ = await vm.saveSignatures()
                        isSaved = true
                    }
                }
            }
        }
        .navigationTitle("Подписи")
        .alert("Успешно сохранено", isPresented: $isSaved) {
            Button("ОК", role: .cancel) { dismiss() }
        }
    }
}

struct AliasesManagerView: View {
    @ObservedObject var vm: SettingsViewModel
    private let repo = SettingsRepository()
    @State private var newAlias = ""
    @State private var aliasPassword = ""

    var body: some View {
        List {
            Section("Активные псевдонимы") {
                ForEach(vm.aliases) { alias in
                    Text(alias.email)
                        .swipeActions {
                            Button(role: .destructive) {
                                Task { await vm.deleteAlias(alias.email) }
                            } label: { Label("Удалить", systemImage: "trash") }
                        }
                }
            }

            Section("Добавить новый псевдоним") {
                TextField("alias@xyecoc.com", text: $newAlias)
                    .textInputAutocapitalization(.never)
                SecureField("Пароль", text: $aliasPassword)
                Button("Создать псевдоним") {
                    Task {
                        let resp = await repo.createAlias(email: newAlias, password: aliasPassword)
                        if resp.isSuccess() {
                            let updated = await repo.fetchAddresses()
                            if let list = updated.addresses { vm.aliases = list }
                            newAlias = ""
                            aliasPassword = ""
                        }
                    }
                }
                .disabled(newAlias.isEmpty || aliasPassword.isEmpty)
            }
        }
        .navigationTitle("Псевдонимы")
    }
}

struct FoldersAndTagsView: View {
    @ObservedObject var vm: SettingsViewModel
    @State private var newFolderName = ""
    @State private var newTagName = ""
    @State private var newTagColorHex = "#18C9E1"

    var body: some View {
        List {
            Section("Пользовательские папки") {
                ForEach(vm.folders) { folder in
                    Text(folder.name)
                        .swipeActions {
                            Button(role: .destructive) {
                                Task { await vm.deleteFolder(folder.name) }
                            } label: { Label("Удалить", systemImage: "trash") }
                        }
                }
                HStack {
                    TextField("Название папки", text: $newFolderName)
                    Button("Создать") {
                        Task {
                            if await vm.createFolder(newFolderName) {
                                newFolderName = ""
                            }
                        }
                    }
                    .disabled(newFolderName.isEmpty)
                }
            }

            Section("Теги") {
                ForEach(vm.tags) { tag in
                    HStack {
                        Circle().fill(Color(hex: tag.color) ?? .gray).frame(width: 10, height: 10)
                        Text(tag.name)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            Task { await vm.deleteTag(id: tag.id) }
                        } label: { Label("Удалить", systemImage: "trash") }
                    }
                }
                HStack {
                    TextField("Имя тега", text: $newTagName)
                    Button("Создать") {
                        Task {
                            if await vm.createTag(name: newTagName, colorHex: newTagColorHex) {
                                newTagName = ""
                            }
                        }
                    }
                    .disabled(newTagName.isEmpty)
                }
            }
        }
        .navigationTitle("Папки и теги")
    }
}

struct FeedbackSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let repo = SettingsRepository()
    @State private var subject = ""
    @State private var message = ""
    @State private var type = "question"
    @State private var isSent = false

    var body: some View {
        NavigationStack {
            Form {
                Picker("Категория", selection: $type) {
                    Text("Вопрос").tag("question")
                    Text("Ошибка").tag("bug")
                    Text("Предложение").tag("feedback")
                }
                TextField("Тема обращения", text: $subject)
                TextEditor(text: $message)
                    .frame(minHeight: 120)

                Button("Отправить обращение") {
                    Task {
                        let resp = await repo.sendFeedback(type: type, subject: subject, message: message)
                        if resp.isSuccess() {
                            isSent = true
                        }
                    }
                }
                .disabled(subject.isEmpty || message.isEmpty)
            }
            .navigationTitle("Обратная связь")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
            }
            .alert("Обращение отправлено", isPresented: $isSent) {
                Button("ОК", role: .cancel) { dismiss() }
            }
        }
    }
}