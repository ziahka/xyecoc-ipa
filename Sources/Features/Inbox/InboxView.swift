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
    @Published var isBatchProcessing = false

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
    }

    func reload() async {
        let all = await db.mails(folder: currentFolder)
        let q = searchQuery.trimmingCharacters(in: .whitespaces)
        if q.isEmpty {
            mails = all
        } else {
            mails = all.filter {
                $0.displayName().range(of: q, options: .caseInsensitive) != nil ||
                $0.displaySubject().range(of: q, options: .caseInsensitive) != nil ||
                $0.snippet.range(of: q, options: .caseInsensitive) != nil
            }
        }
        folders = await db.folders()
        tags = await db.tags()
    }

    func selectFolder(_ folder: String) {
        guard folder != currentFolder else { return }
        currentFolder = folder
        filterUnreadOnly = false
        Task { await reload(); await refresh() }
    }

    func onSearchChanged(_ q: String) {
        searchQuery = q
        Task {
            await reload()
            _ = await repo.fetchMails(folder: currentFolder, searchText: q.isEmpty ? nil : q)
            await reload()
        }
    }

    func refresh() async {
        isRefreshing = true
        _ = await repo.fetchMails(folder: currentFolder,
                                  searchText: searchQuery.isEmpty ? nil : searchQuery)
        isRefreshing = false
        await reload()
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

    func batchDelete(ids: Set<Int64>) async {
        guard !ids.isEmpty else { return }
        isBatchProcessing = true
        defer { isBatchProcessing = false }

        _ = await repo.batchDeleteMails(mailIds: Array(ids), folder: currentFolder)
        await reload()
    }

    func batchSetRead(ids: Set<Int64>, read: Bool) async {
        guard !ids.isEmpty else { return }
        isBatchProcessing = true
        defer { isBatchProcessing = false }

        for id in ids {
            _ = await repo.setReadStatus(mailId: id, read: read, folder: currentFolder)
        }
        await reload()
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

// MARK: - Screen

struct InboxView: View {

    @ObservedObject var accounts: AccountStore
    @StateObject private var vm = InboxViewModel()

    @State private var showCompose = false
    @State private var showAccounts = false
    @State private var composeSeed: ComposeSeed?

    @State private var isSelectionMode = false
    @State private var selectedIds: Set<Int64> = []

    private var searchBinding: Binding<String> {
        Binding(get: { vm.searchQuery }, set: { vm.onSearchChanged($0) })
    }

    private var folderTitle: String {
        if isSelectionMode {
            return selectedIds.isEmpty ? "Выберите письма" : "Выбрано: \(selectedIds.count)"
        }
        return systemFolders.first(where: { $0.id == vm.currentFolder })?.title ?? vm.currentFolder
    }

    private var activeInitial: String {
        String(accounts.activeEmail?.first.map { String($0).uppercased() } ?? "?")
    }

    var body: some View {
        List(selection: $selectedIds) {
            ForEach(vm.displayedMails) { mail in
                NavigationLink {
                    MailReaderView(mailId: mail.id) { Task { await vm.reload() } }
                } label: {
                    MailRowView(state: MailRowState(mail: mail))
                }
                Group {
                    if isSelectionMode {
                        MailRow(mail: mail)
                    } else {
                        NavigationLink {
                            MailReaderView(mailId: mail.id) { Task { await vm.reload() } }
                        } label: {
                            MailRow(mail: mail)
                        }
                    }
                }
                .tag(mail.id)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 12))
                .contextMenu {
                    if !isSelectionMode {
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
                                UIPasteboard.general.string = mail.fromEmail
                                Haptics.light()
                            } label: {
                                Label("Скопировать email отправителя", systemImage: "doc.on.doc")
                            }
                        }

                        Divider()

                        Button(role: .destructive) {
                            Haptics.warning()
                            vm.delete(mail)
                        } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    if !isSelectionMode {
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
                        }.tint(.orange)
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    if !isSelectionMode {
                        Button {
                            Haptics.light()
                            vm.setRead(mail, !mail.read)
                        } label: {
                            Label(mail.read ? "Не прочитано" : "Прочитано",
                                  systemImage: mail.read ? "envelope.badge" : "envelope.open")
                        }.tint(.blue)
                        Button {
                            Haptics.light()
                            vm.toggleStar(mail)
                        } label: {
                            Label("Важное", systemImage: "star")
                        }.tint(.yellow)
                    }
                }
                .onAppear {
                    if mail.id == vm.displayedMails.last?.id {
                        Task { await vm.loadMore() }
                    }
                }
            }
        }
        .listStyle(.plain)
        .environment(\.editMode, .constant(isSelectionMode ? .active : .inactive))
        .animation(.easeInOut(duration: 0.2), value: isSelectionMode)
        .animation(.default, value: vm.displayedMails)
        .navigationTitle(folderTitle)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: searchBinding, prompt: "Поиск в почте")
        .refreshable { await vm.refresh() }
        .safeAreaInset(edge: .top) {
            if !isSelectionMode {
                folderChips
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isSelectionMode {
                bottomActionBar
            }
        }
        .overlay {
            if vm.displayedMails.isEmpty { emptyState }
        }
        .overlay(alignment: .bottomTrailing) {
            if !isSelectionMode { composeButton }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if isSelectionMode {
                    Button(selectedIds.count == vm.displayedMails.count ? "Снять все" : "Все") {
                        Haptics.light()
                        if selectedIds.count == vm.displayedMails.count {
                            selectedIds.removeAll()
                        } else {
                            selectedIds = Set(vm.displayedMails.map(\.id))
                        }
                    }
                } else {
                    folderMenu
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(isSelectionMode ? "Готово" : "Выбрать") {
                    Haptics.light()
                    withAnimation {
                        isSelectionMode.toggle()
                        if !isSelectionMode {
                            selectedIds.removeAll()
                        }
                    }
                }
                .fontWeight(isSelectionMode ? .semibold : .regular)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if !isSelectionMode {
                    overflowMenu
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if !isSelectionMode {
                    accountButton
                }
            }
        }
        .task { await vm.startIfNeeded() }
        .onAppear { Task { await vm.reload() } }
        .sheet(isPresented: $showCompose, onDismiss: { Task { await vm.refresh() } }) {
            ComposeView()
        }
        .sheet(item: $composeSeed, onDismiss: { Task { await vm.refresh() } }) { seed in
            ComposeView(seed: seed)
        }
        .sheet(isPresented: $showAccounts) {
            AccountSwitcherView(accounts: accounts)
        }
    }

    // MARK: - Bottom Action Bar

    private var bottomActionBar: some View {
        HStack {
            Button {
                Haptics.light()
                let ids = selectedIds
                Task {
                    await vm.batchSetRead(ids: ids, read: true)
                    selectedIds.removeAll()
                    isSelectionMode = false
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "envelope.open")
                        .font(.system(size: 18))
                    Text("Прочитано")
                        .font(.caption2)
                }
            }
            .disabled(selectedIds.isEmpty || vm.isBatchProcessing)

            Spacer()

            Button {
                Haptics.light()
                let ids = selectedIds
                Task {
                    await vm.batchSetRead(ids: ids, read: false)
                    selectedIds.removeAll()
                    isSelectionMode = false
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "envelope.badge")
                        .font(.system(size: 18))
                    Text("Не прочитано")
                        .font(.caption2)
                }
            }
            .disabled(selectedIds.isEmpty || vm.isBatchProcessing)

            Spacer()

            Button(role: .destructive) {
                Haptics.warning()
                let ids = selectedIds
                Task {
                    await vm.batchDelete(ids: ids)
                    selectedIds.removeAll()
                    isSelectionMode = false
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "trash")
                        .font(.system(size: 18))
                    Text("В корзину")
                        .font(.caption2)
                }
            }
            .disabled(selectedIds.isEmpty || vm.isBatchProcessing)
        }
        .padding(.horizontal, 32)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .top)
    }

    private func makeReplySeed(for mail: MailItem) -> ComposeSeed {
        let subject = mail.displaySubject()
        let reSubject = subject.lowercased().hasPrefix("re:") ? subject : "Re: \(subject)"
        let recipient = mail.fromEmail.isEmpty ? mail.sender : mail.fromEmail
        return ComposeSeed(to: recipient, subject: reSubject, body: "")
    }

    // MARK: - Compose FAB

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
            Text(activeInitial)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Color.accentColor, in: Circle())
        }
    }

    // MARK: - Chips + menus

    private var folderChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("Входящие", active: vm.currentFolder == "inbox" && !vm.filterUnreadOnly) {
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

    private func chip(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if active { Image(systemName: "checkmark").font(.caption2) }
                Text(title).font(.subheadline)
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

// MARK: - Account switcher

struct AccountSwitcherView: View {
    @ObservedObject var accounts: AccountStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("app_theme") private var selectedTheme: AppTheme = .cyan

    var body: some View {
        NavigationStack {
            List {
                Section("Аккаунты (\(accounts.emails.count)/\(AccountStore.maxAccounts))") {
                    ForEach(accounts.emails, id: \.self) { email in
                        Button {
                            Haptics.light()
                            Task { await accounts.setActive(email); dismiss() }
                        } label: {
                            HStack(spacing: 12) {
                                Text(String(email.first.map { String($0).uppercased() } ?? "?"))
                                    .font(.subheadline.bold()).foregroundStyle(.white)
                                    .frame(width: 34, height: 34)
                                    .background(Color.accentColor, in: Circle())
                                Text(email).foregroundStyle(.primary).lineLimit(1)
                                Spacer()
                                if email == accounts.activeEmail {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                Haptics.warning()
                                Task { await accounts.remove(email) }
                            } label: { Label("Удалить", systemImage: "trash") }
                        }
                    }
                }

                Section("Оформление") {
                    Picker("Цвет приложения", selection: $selectedTheme) {
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
                    .onChange(of: selectedTheme) { _ in
                        Haptics.light()
                    }
                }

                Section {
                    NavigationLink {
                        AddAccountView(accounts: accounts)
                    } label: {
                        Label("Добавить аккаунт", systemImage: "plus.circle")
                    }
                    .disabled(!accounts.canAddAccount)

                    Button(role: .destructive) {
                        Haptics.warning()
                        Task { await accounts.logoutActive() }
                    } label: {
                        Label("Выйти из текущего", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Почтовые ящики")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        Haptics.light()
                        dismiss()
                    }
                }
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