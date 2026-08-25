import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var email: String = ""
    @Published var reserveEmail: String = ""
    @Published var signatureReply: String = ""
    @Published var signatureNew: String = ""
    @Published var is2FAEnabled: Bool = false
    @Published var aliases: [AliasItem] = []
    @Published var folders: [Folder] = []
    @Published var tags: [Tag] = []
    @Published var isLoading: Bool = false

    private let repo = SettingsRepository()
    private let db = MailDatabase.shared

    func load() async {
        isLoading = true
        defer { isLoading = false }

        if let profile = await repo.fetchProfile() {
            email = profile.email ?? KeychainManager.shared.activeEmail() ?? ""
            reserveEmail = profile.reserveEmail ?? ""
            signatureReply = profile.signatureReply ?? ""
            signatureNew = profile.signatureNew ?? ""
            is2FAEnabled = profile.twoFactorStatus ?? false
        } else {
            email = KeychainManager.shared.activeEmail() ?? ""
        }

        aliases = await repo.fetchAliases()
        folders = await db.folders()
        tags = await db.tags()
    }

    func saveSignatures() async -> Bool {
        await repo.updateSignatures(reply: signatureReply, new: signatureNew)
    }

    func updatePassword(old: String, new: String) async -> Bool {
        await repo.updatePassword(old: old, new: new)
    }

    func updateReserveEmail(password: String, newReserve: String) async -> Bool {
        let ok = await repo.setReserveEmail(password: password, email: newReserve)
        if ok { reserveEmail = newReserve }
        return ok
    }

    func disable2FA(password: String) async -> Bool {
        let ok = await repo.disable2FA(password: password)
        if ok { is2FAEnabled = false }
        return ok
    }

    func deleteAlias(_ email: String) async {
        if await repo.deleteAlias(email: email) {
            aliases.removeAll { $0.email == email }
        }
    }

    func createFolder(_ name: String) async {
        if await repo.createFolder(name: name) {
            folders = await db.folders()
        }
    }

    func deleteFolder(_ name: String) async {
        if await repo.deleteFolder(name: name) {
            folders = await db.folders()
        }
    }

    func createTag(name: String, color: String) async {
        if await repo.createTag(name: name, colorHex: color) {
            tags = await db.tags()
        }
    }

    func deleteTag(id: Int64) async {
        if await repo.deleteTag(id: id) {
            tags = await db.tags()
        }
    }

    func deleteAccount(password: String) async -> Bool {
        await repo.deleteAccount(password: password)
    }
}

struct SettingsView: View {
    @ObservedObject var accounts: AccountStore
    @StateObject private var vm = SettingsViewModel()
    @ObservedObject private var security = SecurityManager.shared

    @AppStorage("app_theme") private var selectedTheme: AppTheme = .cyan[cite: 1, 3]
    @AppStorage("app_language") private var selectedLanguage: AppLanguage = .ru[cite: 3, 6]

    @State private var showPasswordSheet = false
    @State private var showReserveSheet = false
    @State private var show2FASheet = false
    @State private var showSetPinSheet = false
    @State private var showFeedbackSheet = false
    @State private var showDeleteAlert = false
    @State private var deletePassword = ""

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
        .navigationTitle("Настройки")[cite: 3, 6]
        .task { await vm.load() }
        .sheet(isPresented: $showPasswordSheet) { ChangePasswordSheet(vm: vm) }
        .sheet(isPresented: $showReserveSheet) { ReserveEmailSheet(vm: vm) }
        .sheet(isPresented: $show2FASheet) { TwoFactorSetupSheet(vm: vm) }
        .sheet(isPresented: $showFeedbackSheet) { FeedbackSheet() }
        .sheet(isPresented: $showSetPinSheet) { pinSetupSheet }
        .alert("Удаление аккаунта", isPresented: $showDeleteAlert) {
            SecureField("Пароль от аккаунта", text: $deletePassword)
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
            Text("Это действие безвозвратно удалит почтовый ящик и все связанные письма.")
        }
    }

    private var accountSection: some View {
        Section("Аккаунт") {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(AvatarGenerator.backgroundColor(for: vm.email))
                        .frame(width: 48, height: 48)
                    Text(AvatarGenerator.initials(displayName: vm.email, email: vm.email))
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(vm.email.isEmpty ? "Загрузка..." : vm.email)
                        .font(.subheadline.bold())
                    Text("Основной адрес")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)

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
                    Text(lang.title).tag(lang)[cite: 3, 6]
                }
            }
        }
    }

    private var securitySection: some View {
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
            } else {
                Button("Установить PIN-код") {
                    resetPinFlow()
                    showSetPinSheet = true
                }
            }
        }
    }

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
                    SecureField("Повторите новый пароль", text: $confirmPassword)
                }

                if let error = errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.footnote)
                    }
                }

                Section {
                    Button(isSubmitting ? "Сохранение..." : "Изменить пароль") {
                        guard newPassword == confirmPassword else {
                            errorMessage = "Новые пароли не совпадают"
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
                Section("Новый резервный адрес") {
                    TextField("example@mail.com", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                    SecureField("Подтвердите паролем от аккаунта", text: $password)
                }

                if let err = errorMessage {
                    Text(err).foregroundStyle(.red).font(.footnote)
                }

                Button(isSubmitting ? "Сохранение..." : "Сохранить") {
                    isSubmitting = true
                    Task {
                        if await vm.updateReserveEmail(password: password, newReserve: email) {
                            dismiss()
                        } else {
                            errorMessage = "Ошибка при сохранении. Проверьте пароль."
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

    @State private var qrData: TwoFactorQRData?
    @State private var totpCode = ""
    @State private var password = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if vm.is2FAEnabled {
                    Section("Отключение 2FA") {
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
                    Section("Настройка аутентификатора") {
                        if let qr = qrData {
                            Text("Секретный ключ: \(qr.secret)")
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                            TextField("6-значный код", text: $totpCode)
                                .keyboardType(.numberPad)
                            Button("Активировать") {
                                Task {
                                    if await repo.enable2FA(code: totpCode, secret: qr.secret) {
                                        vm.is2FAEnabled = true
                                        dismiss()
                                    } else {
                                        errorMessage = "Неверный код"
                                    }
                                }
                            }
                            .disabled(totpCode.count != 6)
                        } else {
                            ProgressView("Генерация ключа...")
                        }
                    }
                }

                if let err = errorMessage {
                    Text(err).foregroundStyle(.red).font(.footnote)
                }
            }
            .navigationTitle("Двухфакторная защита")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
            }
            .task {
                if !vm.is2FAEnabled {
                    qrData = await repo.fetch2FAQR()
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
            Section("Подпись для новых писем") {
                TextEditor(text: $vm.signatureNew)
                    .frame(minHeight: 80)
            }
            Section("Подпись для ответов") {
                TextEditor(text: $vm.signatureReply)
                    .frame(minHeight: 80)
            }
            Section {
                Button("Сохранить подписи") {
                    Task {
                        _ = await vm.saveSignatures()
                        isSaved = true
                    }
                }
            }
        }
        .navigationTitle("Подписи")
        .alert("Сохранено", isPresented: $isSaved) {
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
            Section("Ваши псевдонимы") {
                ForEach(vm.aliases) { alias in
                    HStack {
                        Text(alias.email)
                        Spacer()
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            Task { await vm.deleteAlias(alias.email) }
                        } label: { Label("Удалить", systemImage: "trash") }
                    }
                }
            }

            Section("Добавить псевдоним") {
                TextField("alias@domain.com", text: $newAlias)
                    .textInputAutocapitalization(.never)
                SecureField("Пароль", text: $aliasPassword)
                Button("Создать") {
                    Task {
                        if await repo.createAlias(email: newAlias, password: aliasPassword) {
                            vm.aliases = await repo.fetchAliases()
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
    @State private var newTagColor = "#18C9E1"

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
                    TextField("Имя новой папки", text: $newFolderName)
                    Button("Создать") {
                        Task {
                            await vm.createFolder(newFolderName)
                            newFolderName = ""
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
                            await vm.createTag(name: newTagName, color: newTagColor)
                            newTagName = ""
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
    @State private var type = "feedback"
    @State private var isSent = false

    var body: some View {
        NavigationStack {
            Form {
                Picker("Тип обращения", selection: $type) {
                    Text("Отзыв").tag("feedback")
                    Text("Ошибка").tag("bug")
                    Text("Вопрос").tag("question")
                }
                TextField("Тема", text: $subject)
                TextEditor(text: $message)
                    .frame(minHeight: 120)

                Button("Отправить") {
                    Task {
                        if await repo.sendFeedback(type: type, subject: subject, message: message) {
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
            .alert("Отправлено", isPresented: $isSent) {
                Button("ОК", role: .cancel) { dismiss() }
            }
        }
    }
}