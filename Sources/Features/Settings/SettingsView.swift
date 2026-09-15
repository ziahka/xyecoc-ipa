import SwiftUI
import UIKit

// MARK: - ViewModel

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var email: String = ""
    @Published var reserveEmail: String = ""
    @Published var signature: String = ""
    @Published var signatureReplyEnabled: Bool = true
    @Published var signatureNewEnabled: Bool = true
    @Published var is2FAEnabled: Bool = false
    @Published var aliases: [AliasAddress] = []
    @Published var folders: [Folder] = []
    @Published var tags: [Tag] = []
    @Published var isLoading: Bool = false
    @Published var storageUsed: Double = 0
    @Published var storageTotal: Int64 = 0
    @Published var localCacheSize: String = "…"

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
            self.signature = resp.signature ?? ""
            self.signatureReplyEnabled = resp.signatureReply ?? true
            self.signatureNewEnabled = resp.signatureNew ?? true
            self.is2FAEnabled = (resp.twoFactor == "1" || resp.twoFactor == "true")
            self.storageUsed = resp.storageUsed ?? 0
            self.storageTotal = resp.storageTotal ?? 0
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
        let resp = await repo.updateSignatures(signature: signature, reply: signatureReplyEnabled, new: signatureNewEnabled)
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

    func computeCacheSize() async {
        let size = await db.totalCacheSizeBytes()
        localCacheSize = DateUtils.formatFileSize(Int64(size))
    }

    func clearLocalCache() async {
        await db.clearAll()
        localCacheSize = DateUtils.formatFileSize(0)
    }

    /// Keeps the home-screen badge in step with the cached unread count
    /// (по «badge_scope»: входящие или все папки) after the user flips the setting.
    func syncIconBadge(enabled: Bool) {
        Task {
            let count: Int
            if !enabled {
                count = 0
            } else if Prefs.badgeScope == .all {
                count = await db.unreadCountAll()
            } else {
                count = await db.unreadCount(folder: "inbox")
            }
            BadgeCounter.set(count)
        }
    }
}

// MARK: - Root Settings Screen

struct SettingsView: View {
    @ObservedObject var accounts: AccountStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = SettingsViewModel()
    @ObservedObject private var security = SecurityManager.shared

    @AppStorage("app_theme") private var selectedTheme: AppTheme = .cyan
    @AppStorage("app_language") private var selectedLanguage: AppLanguage = .ru
    @AppStorage("app_appearance") private var appearance: AppAppearance = .system
    @AppStorage("mail_font_size") private var mailFontSize: MailFontSize = .medium
    @AppStorage("block_remote_images") private var blockRemoteImages = false
    @AppStorage("app_icon_badge") private var appIconBadge = true
    @AppStorage("app_autolock") private var autoLockDelay: AutoLockDelay = .immediately
    @AppStorage("list_density") private var listDensity: ListDensity = .regular
    @AppStorage("row_preview") private var rowPreview: RowPreview = .full
    @AppStorage("group_by_date") private var groupByDate = false
    @AppStorage("sort_order") private var sortOrder: SortOrder = .newest
    @AppStorage("swipe_trailing") private var swipeTrailing: SwipeActionKind = .trash
    @AppStorage("swipe_leading") private var swipeLeading: SwipeActionKind = .copy
    @AppStorage("start_folder") private var startFolder: StartFolder = .inbox
    @AppStorage("poll_interval") private var pollInterval: PollInterval = .s30
    @AppStorage("badge_scope") private var badgeScope: BadgeScope = .inbox
    @AppStorage("undo_send") private var undoSend: UndoSendWindow = .off
    @AppStorage("confirm_send") private var confirmSend = false
    @AppStorage("privacy_switcher") private var privacySwitcher = false
    @AppStorage("haptics_enabled") private var hapticsEnabled = true
    @AppStorage("notify_new_mail") private var notifyNewMail = true

    @State private var showPasswordSheet = false
    @State private var showReserveSheet = false
    @State private var show2FASheet = false
    @State private var showSetPinSheet = false
    @State private var showFeedbackSheet = false
    @State private var showDeleteAlert = false
    @State private var showClearCacheAlert = false
    @State private var deletePassword = ""

    @State private var newPin = ""
    @State private var confirmPin = ""
    @State private var pinStep = 0
    @State private var pinError: String?

    var body: some View {
        NavigationStack {
            List {
                accountSection
                appearanceAndLangSection
                AppIconPickerView()
                securitySection
                privacySection
                listSection
                sendingSection
                mailManagementSection
                storageAndCacheSection
                communitySection
                appAndDestructiveSection
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Готово") {
                        dismiss()
                    }
                }
            }
        }
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
        .alert("Очистить локальный кэш?", isPresented: $showClearCacheAlert) {
            Button("Очистить", role: .destructive) {
                Task { await vm.clearLocalCache() }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Письма и вложения исчезнут с устройства. При следующем обновлении список подтянется с сервера заново.")
        }
    }

    private var accountSection: some View {
        Section("Аккаунт") {
            HStack(spacing: 14) {
                AvatarView(email: vm.email, displayName: vm.email, size: 48)

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
                        Circle().fill(theme.color).frame(width: 14, height: 14)
                        Text(theme.title)
                    }
                    .tag(theme)
                }
            }

            Picker("Оформление", selection: $appearance) {
                ForEach(AppAppearance.allCases) { a in
                    Text(a.title).tag(a)
                }
            }

            Picker("Язык интерфейса", selection: $selectedLanguage) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.title).tag(lang)
                }
            }

            Picker("Размер текста писем", selection: $mailFontSize) {
                ForEach(MailFontSize.allCases) { size in
                    Text(size.title).tag(size)
                }
            }

            Toggle(isOn: $hapticsEnabled) {
                Label("Вибрация", systemImage: "iphone.radiowaves.left.and.right")
            }
        }
    }

    @ViewBuilder
    private var securitySection: some View {
        Section {
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

            Picker("Блокировать", selection: $autoLockDelay) {
                ForEach(AutoLockDelay.allCases) { delay in
                    Text(delay.title).tag(delay)
                }
            }
        } header: {
            Text("Безопасность устройства")
        } footer: {
            Text("Через выбранное время после ухода в фон приложение потребует PIN или биометрию при возврате.")
        }
    }

    private var privacySection: some View {
        Section {
            Toggle(isOn: $blockRemoteImages) {
                Label("Блокировать внешние изображения", systemImage: "photo.badge.arrow.down")
            }

            Toggle(isOn: $privacySwitcher) {
                Label("Скрывать в переключателе задач", systemImage: "eye.slash")
            }
        } header: {
            Text("Приватность")
        } footer: {
            Text("Внешние картинки в письмах не будут загружаться — это скрывает отслеживающие пиксели. Изображения с серверов xyecoc.com продолжат отображаться. Щит закрывает письма в мультизадачности.")
        }
    }

    /// Список: плотность, превью, группировка, сортировка, свайпы.
    private var listSection: some View {
        Section {
            Picker("Плотность списка", selection: $listDensity) {
                ForEach(ListDensity.allCases) { d in
                    Text(d.title).tag(d)
                }
            }

            Picker("Превью письма", selection: $rowPreview) {
                ForEach(RowPreview.allCases) { p in
                    Text(p.title).tag(p)
                }
            }

            Toggle(isOn: $groupByDate) {
                Label("Группировать по датам", systemImage: "calendar")
            }

            Picker("Сортировка", selection: $sortOrder) {
                ForEach(SortOrder.allCases) { s in
                    Text(s.title).tag(s)
                }
            }

            Picker("Свайп влево (справа)", selection: $swipeTrailing) {
                ForEach(SwipeActionKind.allCases) { a in
                    Text(a.title).tag(a)
                }
            }

            Picker("Свайп вправо (слева)", selection: $swipeLeading) {
                ForEach(SwipeActionKind.allCases) { a in
                    Text(a.title).tag(a)
                }
            }
        } header: {
            Text("Список писем")
        } footer: {
            Text("Первое действие свайпа выполняется полным свайпом. Изменения применяются к любому списку писем.")
        }
    }

    /// Отправка: окно отмены и подтверждение.
    private var sendingSection: some View {
        Section {
            Picker("Отмена отправки", selection: $undoSend) {
                ForEach(UndoSendWindow.allCases) { w in
                    Text(w.title).tag(w)
                }
            }

            Toggle(isOn: $confirmSend) {
                Label("Подтверждать отправку", systemImage: "checkmark.seal")
            }
        } header: {
            Text("Отправка")
        } footer: {
            Text("После нажатия «отправить» письмо уходит через выбранное время — его можно успеть отменить.")
        }
    }

    private var mailManagementSection: some View {
        Section {
            Toggle(isOn: $appIconBadge) {
                Label("Бейдж непрочитанных на иконке", systemImage: "app.badge")
            }
            .onChange(of: appIconBadge) { enabled in
                vm.syncIconBadge(enabled: enabled)
            }

            Picker("Бейдж считает", selection: $badgeScope) {
                ForEach(BadgeScope.allCases) { s in
                    Text(s.title).tag(s)
                }
            }

            Picker("Папка при запуске", selection: $startFolder) {
                ForEach(StartFolder.allCases) { f in
                    Text(f.title).tag(f)
                }
            }

            Picker("Автообновление", selection: $pollInterval) {
                ForEach(PollInterval.allCases) { i in
                    Text(i.title).tag(i)
                }
            }

            Toggle(isOn: $notifyNewMail) {
                Label("Сообщать о новых письмах", systemImage: "envelope.badge")
            }

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

            NavigationLink {
                BlockedSendersView()
            } label: {
                Label("Чёрный список отправителей", systemImage: "person.slash")
            }
        } header: {
            Text("Почта")
        } footer: {
            Text("«Сообщать о новых письмах» показывает тост, когда опрос замечает новое входящее. При «вручную» письма обновляются потягиванием списка.")
        }
    }

    private var storageAndCacheSection: some View {
        Section("Хранилище") {
            if vm.storageTotal > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Занято")
                        Spacer()
                        Text("\(String(format: "%.1f", vm.storageUsed)) / \(DateUtils.formatFileSize(vm.storageTotal))")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    ProgressView(value: vm.storageUsed, total: Double(vm.storageTotal))
                        .tint(vm.storageUsed / Double(vm.storageTotal) > 0.85 ? .red : .accentColor)
                }
                .padding(.vertical, 4)
            }

            HStack {
                Label("Локальный кэш", systemImage: "internaldrive")
                Spacer()
                Text(vm.localCacheSize)
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Button(role: .destructive) {
                showClearCacheAlert = true
            } label: {
                Label("Очистить кэш", systemImage: "trash.circle")
            }
        }
        .task { await vm.computeCacheSize() }
    }

    private var communitySection: some View {
        Section("Сообщество") {
            if let serviceURL = URL(string: "https://t.me/xyecoc") {
                Link(destination: serviceURL) {
                    HStack {
                        Label("Telegram сервиса", systemImage: "paperplane")
                        Spacer()
                        Image(systemName: "arrow.up.forward.app")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let appURL = URL(string: "https://t.me/xyecoc_ipa") {
                Link(destination: appURL) {
                    HStack {
                        Label("Telegram приложения", systemImage: "paperplane.fill")
                        Spacer()
                        Image(systemName: "arrow.up.forward.app")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
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
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.1.0")
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
                        if await vm.updateReserveEmail(password: password, newEmail: email) {
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

    @State private var qrData: TwoFactorQrData?
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
                            HStack {
                                Text("Секретный ключ: \(qr.secret)")
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                                Spacer()
                                Button {
                                    ClipboardManager.shared.copySecurely(text: qr.secret)
                                    Haptics.medium()
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.caption)
                                }
                                .buttonStyle(.borderless)
                            }
                            TextField("6-значный код", text: $totpCode)
                                .keyboardType(.numberPad)
                            Button("Активировать") {
                                Task {
                                    let resp = await repo.enable2FA(code: totpCode, secret: qr.secret)
                                    if resp.isSuccess() {
                                        vm.is2FAEnabled = true
                                        dismiss()
                                    } else {
                                        errorMessage = resp.message ?? "Неверный код"
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
            Section("Текст подписи") {
                TextEditor(text: $vm.signature)
                    .frame(minHeight: 100)
            }
            Section("Когда добавлять подпись") {
                Toggle("В новых письмах", isOn: $vm.signatureNewEnabled)
                Toggle("В ответах", isOn: $vm.signatureReplyEnabled)
            }
            Section {
                Button("Сохранить") {
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
                TextField("alias@xyecoc.com", text: $newAlias)
                    .textInputAutocapitalization(.never)
                SecureField("Пароль", text: $aliasPassword)
                Button("Создать") {
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
                            if await vm.createTag(name: newTagName, colorHex: newTagColor) {
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
            .alert("Отправлено", isPresented: $isSent) {
                Button("ОК", role: .cancel) { dismiss() }
            }
        }
    }
}