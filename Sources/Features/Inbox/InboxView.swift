import SwiftUI

// MARK: - ViewModel

@MainActor
final class InboxViewModel: ObservableObject {
    @Published var mails: [MailItem] = []
    @Published var folders: [Folder] = []
    @Published var tags: [Tag] = []
    @Published var currentFolder: String = "inbox"
    @Published var searchQuery: String = ""
    @Published var isRefreshing = false
    @Published var filterUnreadOnly = false

    // Refresh throttle + toast
    @Published var refreshToast: String?
    private var lastRefreshDate: Date = .distantPast
    private static let refreshCooldown: TimeInterval = 3

    // Batch selection
    @Published var isSelecting = false
    @Published var selectedIds: Set<Int64> = []

    // Search scope
    @Published var searchScope: SearchScope = .all

    // Polling
    @Published var unreadBadge: Int = 0
    private var pollingTask: Task<Void, Never>?
    private static let pollingInterval: UInt64 = 30_000_000_000 // 30 sec

    private let repo = MailRepository()
    private let db = MailDatabase.shared
    private var didStart = false

    var displayedMails: [MailItem] {
        filterUnreadOnly ? mails.filter { !$0.read } : mails
    }

    func startIfNeeded() async {
        guard !didStart else { await reload(); return }
        didStart = true
        await reload()
        await refresh()
        startPolling()
    }

    func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.pollingInterval)
                guard !Task.isCancelled else { return }
                _ = await repo.fetchMails(folder: "inbox")
                await reload()
                unreadBadge = await db.unreadCount(folder: "inbox")
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func reload() async {
        let all = await db.mails(folder: currentFolder)
        let q = searchQuery.trimmingCharacters(in: .whitespaces)
        if q.isEmpty {
            mails = all
        } else {
            mails = all.filter { mail in
                switch searchScope {
                case .all:
                    return mail.displayName().range(of: q, options: .caseInsensitive) != nil
                        || mail.displaySubject().range(of: q, options: .caseInsensitive) != nil
                        || mail.snippet.range(of: q, options: .caseInsensitive) != nil
                case .sender:
                    return mail.displayName().range(of: q, options: .caseInsensitive) != nil
                        || mail.fromEmail.range(of: q, options: .caseInsensitive) != nil
                case .subject:
                    return mail.displaySubject().range(of: q, options: .caseInsensitive) != nil
                case .unread:
                    return !mail.read && (
                        mail.displayName().range(of: q, options: .caseInsensitive) != nil
                        || mail.displaySubject().range(of: q, options: .caseInsensitive) != nil)
                case .attachments:
                    return mail.hasAttachments && (
                        mail.displayName().range(of: q, options: .caseInsensitive) != nil
                        || mail.displaySubject().range(of: q, options: .caseInsensitive) != nil)
                }
            }
        }
        folders = await db.folders()
        tags = await db.tags()
        unreadBadge = await db.unreadCount(folder: "inbox")
    }

    func selectFolder(_ folder: String) {
        guard folder != currentFolder else { return }
        currentFolder = folder
        filterUnreadOnly = false
        exitSelection()
        Task { await reload(); await refresh() }
    }

    private var searchTask: Task<Void, Never>?

    func onSearchChanged(_ q: String) {
        searchQuery = q
        searchTask?.cancel()
        searchTask = Task {
            await reload()
            guard !Task.isCancelled else { return }
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            _ = await repo.fetchMails(folder: currentFolder, searchText: q.isEmpty ? nil : q)
            guard !Task.isCancelled else { return }
            await reload()
        }
    }

    func moveToTrash(_ mail: MailItem) {
        withAnimation(.easeInOut(duration: 0.25)) {
            mails.removeAll { $0.id == mail.id }
        }
        Task {
            _ = await repo.performMailAction(mailId: mail.id, action: "move-to-folder",
                                             value: .string("trash"), folder: currentFolder)
            await reload()
        }
    }

    func refresh() async {
        let now = Date()
        guard now.timeIntervalSince(lastRefreshDate) >= Self.refreshCooldown else {
            showToast("Подождите пару секунд…")
            return
        }
        lastRefreshDate = now
        isRefreshing = true
        let oldCount = mails.count
        _ = await repo.fetchMails(folder: currentFolder,
                                  searchText: searchQuery.isEmpty ? nil : searchQuery)
        isRefreshing = false
        await reload()
        let diff = mails.count - oldCount
        if diff > 0 {
            showToast("Новых писем: \(diff)")
        } else {
            showToast("Нет новых писем")
        }
    }

    private func showToast(_ text: String) {
        refreshToast = text
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if refreshToast == text { refreshToast = nil }
        }
    }

    func loadMore() async {
        guard searchQuery.isEmpty, let cursor = mails.map(\.id).min() else { return }
        _ = await repo.fetchMails(folder: currentFolder, page: 1, lastMailId: cursor)
        await reload()
    }

    func toggleStar(_ mail: MailItem) {
        Task {
            _ = await repo.performMailAction(mailId: mail.id, action: "important", folder: currentFolder)
            await reload()
        }
    }

    func delete(_ mail: MailItem) {
        Task {
            _ = await repo.performMailAction(mailId: mail.id, action: "delete", folder: currentFolder)
            await reload()
        }
    }

    func setRead(_ mail: MailItem, _ read: Bool) {
        Task {
            _ = await repo.setReadStatus(mailId: mail.id, read: read, folder: currentFolder)
            await reload()
        }
    }

    func moveToSpam(_ mail: MailItem) {
        Task {
            _ = await repo.performMailAction(mailId: mail.id, action: "move-to-folder",
                                             value: .string("spam"), folder: currentFolder)
            await reload()
        }
    }

    func markAllRead() {
        Task { _ = await repo.markAllRead(); await refresh() }
    }

    // MARK: - Batch selection

    func toggleSelection(for mail: MailItem) {
        if selectedIds.contains(mail.id) {
            selectedIds.remove(mail.id)
        } else {
            selectedIds.insert(mail.id)
        }
        if selectedIds.isEmpty { isSelecting = false }
    }

    func enterSelection(_ mail: MailItem) {
        isSelecting = true
        selectedIds = [mail.id]
    }

    func exitSelection() {
        isSelecting = false
        selectedIds.removeAll()
    }

    func selectAll() {
        selectedIds = Set(displayedMails.map(\.id))
    }

    func batchDelete() {
        let ids = Array(selectedIds)
        guard !ids.isEmpty else { return }
        withAnimation { mails.removeAll { ids.contains($0.id) } }
        exitSelection()
        Task {
            _ = await repo.batchDeleteMails(mailIds: ids, folder: currentFolder)
            await reload()
        }
    }

    func batchMarkRead(_ read: Bool) {
        let ids = Array(selectedIds)
        exitSelection()
        Task {
            for id in ids {
                _ = await repo.setReadStatus(mailId: id, read: read, folder: currentFolder)
            }
            await reload()
        }
    }

    func batchMoveToTrash() {
        let ids = Array(selectedIds)
        withAnimation { mails.removeAll { ids.contains($0.id) } }
        exitSelection()
        Task {
            for id in ids {
                _ = await repo.performMailAction(mailId: id, action: "move-to-folder",
                                                 value: .string("trash"), folder: currentFolder)
            }
            await reload()
        }
    }
}

// MARK: - System folders

struct SystemFolder: Identifiable {
    let id: String
    let title: String
    let icon: String
}

let systemFolders: [SystemFolder] = [
    .init(id: "inbox", title: "Входящие", icon: "tray"),
    .init(id: "sent", title: "Отправленные", icon: "paperplane"),
    .init(id: "important", title: "Важные", icon: "star"),
    .init(id: "draft", title: "Черновики", icon: "doc"),
    .init(id: "spam", title: "Спам", icon: "exclamationmark.octagon"),
    .init(id: "trash", title: "Корзина", icon: "trash")
]

// MARK: - Search scope

enum SearchScope: String, CaseIterable {
    case all = "Все"
    case sender = "От кого"
    case subject = "Тема"
    case unread = "Непрочитанные"
    case attachments = "С вложениями"
}

// MARK: - Screen

struct InboxView: View {
    @ObservedObject var accounts: AccountStore
    @StateObject private var vm = InboxViewModel()
    @ObservedObject private var network = NetworkMonitor.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var showCompose = false
    @State private var showAccounts = false
    @State private var showSettings = false
    @State private var composeSeed: ComposeSeed?

    private var searchBinding: Binding<String> {
        Binding(get: { vm.searchQuery }, set: { vm.onSearchChanged($0) })
    }

    private var folderTitle: String {
        systemFolders.first(where: { $0.id == vm.currentFolder })?.title ?? vm.currentFolder
    }

    private var activeInitial: String {
        String(accounts.activeEmail?.first.map { String($0).uppercased() } ?? "?")
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            List {
                ForEach(vm.displayedMails) { mail in
                    if vm.isSelecting {
                        selectableRow(mail)
                    } else {
                        normalRow(mail)
                    }
                }
            }
            .listStyle(.plain)
            .animation(.default, value: vm.displayedMails)
            .navigationTitle(vm.isSelecting ? "\(vm.selectedIds.count) выбрано" : folderTitle)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: searchBinding, prompt: "Поиск в почте")
            .searchScopes($vm.searchScope) {
                ForEach(SearchScope.allCases, id: \.self) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .refreshable { await vm.refresh() }
            .safeAreaInset(edge: .top) {
                VStack(spacing: 0) {
                    if !network.isConnected {
                        HStack(spacing: 6) {
                            Image(systemName: "wifi.slash")
                                .font(.caption)
                            Text("Нет соединения")
                                .font(.caption.weight(.medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.9))
                        .foregroundStyle(.white)
                    }
                    if !vm.isSelecting { folderChips }
                    if vm.isSelecting { batchToolbar }
                }
            }
            .overlay { if vm.displayedMails.isEmpty && !vm.isSelecting { emptyState } }
            .overlay(alignment: .bottomTrailing) {
                if !vm.isSelecting { composeButton }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if vm.isSelecting {
                        Button("Отмена") { vm.exitSelection() }
                    } else {
                        folderMenu
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if vm.isSelecting {
                        Button("Все") { vm.selectAll() }
                    } else {
                        overflowMenu
                    }
                }
                if !vm.isSelecting {
                    ToolbarItem(placement: .navigationBarTrailing) { accountButton }
                }
            }
            .task { await vm.startIfNeeded() }
            .onAppear { Task { await vm.reload() } }
            .onDisappear { vm.stopPolling() }
            .onChange(of: vm.searchScope) { _ in
                Task { await vm.reload() }
            }
            .onChange(of: scenePhase) { phase in
                if phase == .active { vm.startPolling() }
                else if phase == .background { vm.stopPolling() }
            }
            .onReceive(network.restored) {
                Task { await vm.refresh() }
            }
            .sheet(isPresented: $showCompose, onDismiss: { Task { await vm.refresh() } }) {
                ComposeView()
            }
            .sheet(item: $composeSeed, onDismiss: { Task { await vm.refresh() } }) { seed in
                ComposeView(seed: seed)
            }
            .sheet(isPresented: $showAccounts) {
                AccountSwitcherView(accounts: accounts)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(accounts: accounts)
            }

            // Toast
            if let toast = vm.refreshToast {
                Text(toast)
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .shadow(radius: 4)
                    .padding(.bottom, 80)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.25), value: toast)
            }
        }
    }

    // MARK: - Row variants

    @ViewBuilder
    private func normalRow(_ mail: MailItem) -> some View {
        NavigationLink {
            MailReaderView(mailId: mail.id,
                           siblingIds: vm.displayedMails.map(\.id)) { Task { await vm.reload() } }
        } label: {
            MailRowView(state: MailRowState(mail: mail))
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 12))
        .contextMenu {
            Button {
                composeSeed = makeReplySeed(for: mail)
            } label: {
                Label("Ответить", systemImage: "arrowshape.turn.up.left")
            }

            Button {
                Haptics.light()
                vm.setRead(mail, !mail.read)
            } label: {
                Label(
                    mail.read ? "Отметить как непрочитанное" : "Отметить как прочитанное",
                    systemImage: mail.read ? "envelope.badge" : "envelope.open"
                )
            }

            Button {
                Haptics.light()
                vm.toggleStar(mail)
            } label: {
                Label(
                    mail.important ? "Убрать из избранного" : "В избранное",
                    systemImage: mail.important ? "star.slash" : "star"
                )
            }

            if !mail.fromEmail.isEmpty {
                Button {
                    ClipboardManager.shared.copySecurely(text: mail.fromEmail)
                    Haptics.medium()
                } label: {
                    Label("Скопировать email отправителя", systemImage: "doc.on.doc")
                }
            }

            Divider()

            Button { vm.enterSelection(mail) } label: {
                Label("Выделить", systemImage: "checkmark.circle")
            }

            Button(role: .destructive) {
                Haptics.warning()
                vm.delete(mail)
            } label: {
                Label("Удалить", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                Haptics.medium()
                vm.moveToTrash(mail)
            } label: {
                Label("В корзину", systemImage: "trash")
            }.tint(.orange)

            Button(role: .destructive) {
                Haptics.warning()
                vm.delete(mail)
            } label: {
                Label("Удалить", systemImage: "trash")
            }

            Button {
                Haptics.medium()
                vm.moveToSpam(mail)
            } label: {
                Label("Спам", systemImage: "exclamationmark.octagon")
            }.tint(.red)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                Haptics.medium()
                let emailToCopy = mail.fromEmail.isEmpty ? mail.sender : mail.fromEmail
                ClipboardManager.shared.copySecurely(text: emailToCopy)
            } label: {
                Label("Копировать email", systemImage: "doc.on.doc")
            }.tint(.blue)

            Button {
                Haptics.light()
                vm.setRead(mail, !mail.read)
            } label: {
                Label(mail.read ? "Не прочитано" : "Прочитано",
                      systemImage: mail.read ? "envelope.badge" : "envelope.open")
            }.tint(.indigo)
        }
        .onAppear {
            if mail.id == vm.displayedMails.last?.id {
                Task { await vm.loadMore() }
            }
        }
    }

    @ViewBuilder
    private func selectableRow(_ mail: MailItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: vm.selectedIds.contains(mail.id) ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(vm.selectedIds.contains(mail.id) ? Color.accentColor : .secondary)
                .font(.title3)
            MailRowView(state: MailRowState(mail: mail))
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 12))
        .contentShape(Rectangle())
        .onTapGesture { vm.toggleSelection(for: mail) }
    }

    private var batchToolbar: some View {
        HStack(spacing: 0) {
            batchButton(icon: "envelope.open", label: "Прочитать") {
                Haptics.medium(); vm.batchMarkRead(true)
            }
            batchButton(icon: "envelope.badge", label: "Не прочитать") {
                Haptics.medium(); vm.batchMarkRead(false)
            }
            batchButton(icon: "trash", label: "В корзину") {
                Haptics.warning(); vm.batchMoveToTrash()
            }
            batchButton(icon: "trash.fill", label: "Удалить") {
                Haptics.warning(); vm.batchDelete()
            }
        }
        .padding(.vertical, 6)
        .background(.bar)
    }

    private func batchButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.body)
                Text(label).font(.caption2)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(vm.selectedIds.isEmpty)
    }

    private func makeReplySeed(for mail: MailItem) -> ComposeSeed {
        let subject = mail.displaySubject()
        let reSubject = subject.lowercased().hasPrefix("re:") ? subject : "Re: \(subject)"
        let recipient = mail.fromEmail.isEmpty ? (mail.sender) : mail.fromEmail
        return ComposeSeed(to: recipient, subject: reSubject, body: "")
    }

    private var composeButton: some View {
        Button {
            Haptics.light()
            showCompose = true
        } label: {
            Image(systemName: "square.and.pencil")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(Color.accentColor, in: Circle())
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        }
        .padding(20)
    }

    private var accountButton: some View {
        Button {
            Haptics.light()
            showAccounts = true
        } label: {
            if let active = accounts.activeEmail, !active.isEmpty {
                AvatarView(email: active, size: 30)
            } else {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 30, height: 30)
            }
        }
    }

    private var folderChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("Входящие", active: vm.currentFolder == "inbox" && !vm.filterUnreadOnly,
                     badge: vm.unreadBadge > 0 && vm.currentFolder != "inbox" ? vm.unreadBadge : nil) {
                    Haptics.light()
                    vm.filterUnreadOnly = false; vm.selectFolder("inbox")
                }
                chip("Непрочитанные", active: vm.filterUnreadOnly) {
                    Haptics.light()
                    vm.filterUnreadOnly.toggle()
                }
                chip("Важные", active: vm.currentFolder == "important") {
                    Haptics.light()
                    vm.selectFolder("important")
                }
                chip("Отправленные", active: vm.currentFolder == "sent") {
                    Haptics.light()
                    vm.selectFolder("sent")
                }
                chip("Корзина", active: vm.currentFolder == "trash") {
                    Haptics.light()
                    vm.selectFolder("trash")
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .background(.bar)
    }

    private func chip(_ title: String, active: Bool, badge: Int? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if active { Image(systemName: "checkmark").font(.caption2) }
                Text(title).font(.subheadline)
                if let badge, badge > 0 {
                    Text("\(badge)")
                        .font(.caption2.bold())
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(active ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12))
            .foregroundStyle(active ? Color.accentColor : Color.primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var folderMenu: some View {
        Menu {
            Section("Папки") {
                ForEach(systemFolders) { f in
                    Button {
                        Haptics.light()
                        vm.selectFolder(f.id)
                    } label: { Label(f.title, systemImage: f.icon) }
                }
            }
            if !vm.folders.isEmpty {
                Section("Мои папки") {
                    ForEach(vm.folders) { f in
                        Button {
                            Haptics.light()
                            vm.selectFolder(f.name)
                        } label: { Label(f.name, systemImage: "folder") }
                    }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal")
        }
    }

    private var overflowMenu: some View {
        Menu {
            Button {
                Haptics.medium()
                vm.markAllRead()
            } label: {
                Label("Прочитать все", systemImage: "envelope.open")
            }
            Toggle(isOn: Binding(
                get: { vm.filterUnreadOnly },
                set: {
                    Haptics.light()
                    vm.filterUnreadOnly = $0
                }
            )) {
                Label("Только непрочитанные", systemImage: "envelope.badge")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "envelope.open")
                .resizable().scaledToFit().frame(width: 56, height: 56)
                .foregroundStyle(.secondary)
            Text(vm.filterUnreadOnly ? "Нет непрочитанных писем" : "В этой папке нет писем")
                .foregroundStyle(.secondary)
            Button {
                Haptics.light()
                Task { await vm.refresh() }
            } label: {
                Label("Обновить", systemImage: "arrow.clockwise")
            }
        }
        .padding()
    }
}

// MARK: - Shared Views

struct AccountSwitcherView: View {
    @ObservedObject var accounts: AccountStore
    @Environment(\.dismiss) private var dismiss
    @State private var showSettings = false
    @State private var showAddAccount = false

    var body: some View {
        NavigationStack {
            List {
                Section("Почтовые ящики") {
                    ForEach(accounts.emails, id: \.self) { email in
                        HStack(spacing: 12) {
                            AvatarView(email: email, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(email)
                                    .font(.subheadline)
                                    .fontWeight(email == accounts.activeEmail ? .bold : .regular)
                                if email == accounts.activeEmail {
                                    Text("Активен")
                                        .font(.caption2)
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            Spacer()
                            if email == accounts.activeEmail {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Task {
                                await accounts.setActive(email)
                                dismiss()
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await accounts.remove(email) }
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                        }
                    }

                    Button {
                        showAddAccount = true
                    } label: {
                        Label("Добавить аккаунт", systemImage: "plus")
                    }
                }

                Section {
                    Button {
                        showSettings = true
                    } label: {
                        Label("Настройки приложения", systemImage: "gearshape")
                    }
                }
            }
            .navigationTitle("Учетные записи")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(accounts: accounts)
            }
            .sheet(isPresented: $showAddAccount) {
                AddAccountView(accounts: accounts)
            }
        }
    }
}

struct AddAccountView: View {
    @ObservedObject var accounts: AccountStore

    var body: some View {
        LoginFlowView { await accounts.onLoggedIn() }
            .navigationTitle("Новый аккаунт")
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct TagBadge: View {
    let name: String
    let colorHex: String?

    var body: some View {
        let color = Color(hex: colorHex) ?? .gray
        Text(name)
            .font(.caption2).fontWeight(.medium)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(color.opacity(0.18))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}