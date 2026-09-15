import SwiftUI
import UserNotifications

/// Секция списка с группировкой по датам («Сегодня / Вчера / Ранее»).
struct MailSection: Identifiable {
    let id: String
    let title: String
    let mails: [MailItem]
}
import UIKit

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
    @Published var filterAttachments = false

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
    @Published var importantUnread: Int = 0
    /// false, когда сцена в фоне: тосты не видны — уведомляем локальным push.
    @Published var isAppActive = true
    @Published var snoozedCount: Int = 0
    @Published var groupedSections: [MailSection] = []
    private var pollingTask: Task<Void, Never>?

    /// Mirrors the inbox unread count onto the app icon badge. The switch
    /// lives in Settings ("app_icon_badge"); turning it off clears the badge.
    func applyIconBadge(_ count: Int) {
        let enabled = UserDefaults.standard.object(forKey: "app_icon_badge") as? Bool ?? true
        BadgeCounter.set(enabled ? count : 0)
    }

    private let repo = MailRepository()
    private let db = MailDatabase.shared
    private var didStart = false

    var displayedMails: [MailItem] {
        var result = filterUnreadOnly ? mails.filter { !$0.read } : mails
        if filterAttachments {
            result = result.filter { $0.hasAttachments }
        }
        return result
    }

    func startIfNeeded() async {
        guard !didStart else { await reload(); return }
        didStart = true
        applyStartFolder()
        await reload()
        await refresh()
        startPolling()
    }

    /// Папка при запуске — настройка «start_folder»:
    /// входящие / важные / последняя открытая.
    private func applyStartFolder() {
        switch Prefs.startFolder {
        case .inbox:
            break
        case .important:
            currentFolder = "important"
        case .last:
            if let last = UserDefaults.standard.string(forKey: "last_folder") {
                currentFolder = last
            }
        }
    }

    func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task {
            var lastMaxId = await db.maxMailId()
            while !Task.isCancelled {
                // Интервал опроса — настройка «poll_interval»; 0 = вручную.
                let interval = Prefs.pollInterval.seconds
                try? await Task.sleep(nanoseconds: interval > 0 ? interval * 1_000_000_000 : 5_000_000_000)
                guard !Task.isCancelled else { return }
                // Poll the folder the user is actually looking at; the virtual
                // snoozed folder has no server representation.
                if interval > 0 && currentFolder != snoozedFolderId {
                    _ = await repo.fetchMails(folder: currentFolder)
                }
                await reload()
                unreadBadge = await currentBadgeCount()
                // Новые письма: считаем только входящие, чтобы собственные
                // отправки и черновики не считались. В фоне — локальное
                // уведомление, на экране — тост.
                let newMaxId = await db.maxMailId()
                if interval > 0, lastMaxId > 0, newMaxId > lastMaxId, Prefs.notifyNewMail {
                    let fresh = await db.countNewer(than: lastMaxId, inFolder: "inbox")
                    if fresh > 0 {
                        if isAppActive {
                            Haptics.success()
                            showToast("Новые письма: \(fresh)")
                        } else if await Self.notificationsAuthorized() {
                            await Self.postNewMailNotification(count: fresh, maxId: newMaxId)
                        }
                    }
                }
                lastMaxId = newMaxId
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// Разрешены ли локальные уведомления.
    private static func notificationsAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
    }

    /// Локальное уведомление о новых письмах; идентификатор по maxId —
    /// повторные добавления с тем же id заменяют друг друга без спама.
    private static func postNewMailNotification(count: Int, maxId: Int64) async {
        let content = UNMutableNotificationContent()
        content.title = "xyecoc почта"
        content.body = count == 1 ? "Новое письмо" : "Новых писем: \(count)"
        content.sound = .default
        let request = UNNotificationRequest(identifier: "newmail-\(maxId)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    func reload() async {
        applyIconBadge(await currentBadgeCount())
        if currentFolder == snoozedFolderId {
            mails = applySearch(await db.snoozedMails().map { $0.mail })
        } else {
            let all = await db.mails(folder: currentFolder)
            let snoozed = await db.activeSnoozeIds()
            var visible = all.filter { !snoozed.contains($0.id) }
            if !BlockedSendersStore.blocked.isEmpty {
                visible = visible.filter { !BlockedSendersStore.isBlocked(senderEmail(of: $0)) }
            }
            mails = applySearch(sortMails(visible))
        }
        rebuildSections()
        folders = await db.folders()
        tags = await db.tags()
        unreadBadge = await currentBadgeCount()
        importantUnread = await db.unreadCount(folder: "important")
        snoozedCount = await db.activeSnoozeCount()
    }

    /// Бейдж по настройке «badge_scope»: только входящие или все папки.
    private func currentBadgeCount() async -> Int {
        Prefs.badgeScope == .all ? await db.unreadCountAll() : await db.unreadCount(folder: "inbox")
    }

    /// Сортировка списка по настройке «sort_order»;
    /// закреплённые письма всегда идут первыми.
    private func sortMails(_ source: [MailItem]) -> [MailItem] {
        let base: [MailItem]
        switch Prefs.sortOrder {
        case .newest:
            base = source.sorted { $0.id > $1.id }
        case .oldest:
            base = source.sorted { $0.id < $1.id }
        case .unreadFirst:
            base = source.sorted { a, b in
                if a.read != b.read { return !a.read }
                return a.id > b.id
            }
        }
        let pinned = PinnedMailStore.all
        guard !pinned.isEmpty else { return base }
        return base.filter { pinned.contains($0.id) } + base.filter { !pinned.contains($0.id) }
    }

    /// Секции «Сегодня / Вчера / Ранее» по настройке «group_by_date».
    private func rebuildSections() {
        guard Prefs.groupByDate else {
            groupedSections = []
            return
        }
        let cal = Calendar.current
        var today: [MailItem] = []
        var yesterday: [MailItem] = []
        var earlier: [MailItem] = []
        for mail in displayedMails {
            guard let date = DateUtils.parseISO(mail.createdAt) else {
                earlier.append(mail)
                continue
            }
            if cal.isDateInToday(date) {
                today.append(mail)
            } else if cal.isDateInYesterday(date) {
                yesterday.append(mail)
            } else {
                earlier.append(mail)
            }
        }
        var sections: [MailSection] = []
        if !today.isEmpty { sections.append(MailSection(id: "today", title: "Сегодня", mails: today)) }
        if !yesterday.isEmpty { sections.append(MailSection(id: "yesterday", title: "Вчера", mails: yesterday)) }
        if !earlier.isEmpty { sections.append(MailSection(id: "earlier", title: "Ранее", mails: earlier)) }
        groupedSections = sections
    }

    var showGroupedSections: Bool {
        Prefs.groupByDate && !groupedSections.isEmpty && searchQuery.isEmpty
            && currentFolder != snoozedFolderId && !filterUnreadOnly
    }

    private func senderEmail(of mail: MailItem) -> String {
        mail.fromEmail.isEmpty ? mail.sender : mail.fromEmail
    }

    private func folderTitle(for mail: MailItem) -> String {
        systemFolders.first(where: { $0.id == mail.folder })?.title ?? mail.folder
    }

    /// Сервер знает только реальные папки: из виртуальной «Отложенные»
    /// действия уходят с pageId реальной папки письма.
    private func requestFolder(for mail: MailItem) -> String {
        currentFolder == snoozedFolderId ? mail.folder : currentFolder
    }

    private var requestFolderForBatch: String? {
        currentFolder == snoozedFolderId ? nil : currentFolder
    }

    private func applySearch(_ source: [MailItem]) -> [MailItem] {
        let q = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return source }
        return source.filter { mail in
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

    func selectFolder(_ folder: String) {
        guard folder != currentFolder else { return }
        currentFolder = folder
        UserDefaults.standard.set(folder, forKey: "last_folder")
        filterUnreadOnly = false
        filterAttachments = false
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
            // В виртуальной папке «Отложенные» поиск работает только по кэшу.
            guard currentFolder != snoozedFolderId else { return }
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
                                             value: .string("trash"), folder: requestFolder(for: mail))
            await reload()
        }
    }

    func refresh() async {
        // Виртуальная папка «Отложенные» существует только на клиенте.
        guard currentFolder != snoozedFolderId else {
            await reload()
            return
        }
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
        guard currentFolder != snoozedFolderId else { return }
        guard searchQuery.isEmpty, let cursor = mails.map(\.id).min() else { return }
        _ = await repo.fetchMails(folder: currentFolder, page: 1, lastMailId: cursor)
        await reload()
    }

    func toggleStar(_ mail: MailItem) {
        Task {
            _ = await repo.performMailAction(mailId: mail.id, action: "important", folder: requestFolder(for: mail))
            await reload()
        }
    }

    func delete(_ mail: MailItem) {
        Task {
            _ = await repo.performMailAction(mailId: mail.id, action: "delete", folder: requestFolder(for: mail))
            await reload()
        }
    }

    func setRead(_ mail: MailItem, _ read: Bool) {
        Task {
            _ = await repo.setReadStatus(mailId: mail.id, read: read, folder: requestFolder(for: mail))
            await reload()
        }
    }

    func moveToSpam(_ mail: MailItem) {
        Task {
            _ = await repo.performMailAction(mailId: mail.id, action: "move-to-folder",
                                             value: .string("spam"), folder: requestFolder(for: mail))
            await reload()
        }
    }

    func markAllRead() {
        Task {
            let resp = await repo.markAllRead()
            guard resp.error == nil else {
                showToast(resp.message ?? "Не удалось отметить письма")
                return
            }
            // Притягиваем свежие флаги прочтения в локальный кэш.
            _ = await repo.fetchMails(folder: "inbox")
            await reload()
            Haptics.success()
            showToast("Все письма отмечены прочитанными")
        }
    }

    // MARK: - Snooze (локальное откладывание)

    func snooze(_ mail: MailItem, until date: Date) {
        Task {
            await db.snooze(mailId: mail.id, until: date)
            await reload()
            Haptics.medium()
            showToast("Отложено \(DateUtils.snoozeLabel(until: date))")
        }
    }

    func unsnooze(_ mail: MailItem) {
        Task {
            await db.unsnooze(mailId: mail.id)
            await reload()
            Haptics.medium()
            showToast("Вернули в «\(folderTitle(for: mail))»")
        }
    }

    // MARK: - Чёрный список отправителей

    func blockSender(_ mail: MailItem) {
        let email = senderEmail(of: mail)
        guard !email.isEmpty else {
            showToast("Не удалось определить отправителя")
            return
        }
        BlockedSendersStore.block(email)
        withAnimation {
            mails.removeAll { senderEmail(of: $0) == email }
        }
        // Серверная блокировка дополняет локальный фильтр.
        Task {
            _ = await repo.blockSender(mailId: mail.id)
            await reload()
        }
        Haptics.warning()
        showToast("Отправитель заблокирован: \(email)")
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
            _ = await repo.batchDeleteMails(mailIds: ids, folder: requestFolderForBatch)
            await reload()
            showToast("Удалено: \(ids.count)")
        }
    }

    func batchMarkRead(_ read: Bool) {
        let ids = Array(selectedIds)
        exitSelection()
        Task {
            // Параллельные RPC вместо последовательной очереди.
            let repo = self.repo
            let folder = requestFolderForBatch
            await withTaskGroup(of: Void.self) { group in
                for id in ids {
                    group.addTask {
                        _ = await repo.setReadStatus(mailId: id, read: read, folder: folder)
                    }
                }
            }
            await reload()
            showToast(read ? "Прочитано: \(ids.count)" : "Не прочитано: \(ids.count)")
        }
    }

    func batchMoveToTrash() {
        let ids = Array(selectedIds)
        withAnimation { mails.removeAll { ids.contains($0.id) } }
        exitSelection()
        Task {
            let repo = self.repo
            let folder = requestFolderForBatch
            await withTaskGroup(of: Void.self) { group in
                for id in ids {
                    group.addTask {
                        _ = await repo.performMailAction(mailId: id, action: "move-to-folder",
                                                         value: .string("trash"), folder: folder)
                    }
                }
            }
            await reload()
            showToast("В корзине: \(ids.count)")
        }
    }
}

// MARK: - System folders

struct SystemFolder: Identifiable {
    let id: String
    let title: String
    let icon: String
}

/// Виртуальная папка только на клиенте: отложенные письма остаются в своих
/// папках, но прячутся из списков до момента пробуждения.
let snoozedFolderId = "snoozed"

let systemFolders: [SystemFolder] = [
    .init(id: "inbox", title: "Входящие", icon: "tray"),
    .init(id: "sent", title: "Отправленные", icon: "paperplane"),
    .init(id: "important", title: "Важные", icon: "star"),
    .init(id: "draft", title: "Черновики", icon: "doc"),
    .init(id: snoozedFolderId, title: "Отложенные", icon: "clock"),
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
    @State private var showStats = false
    @State private var showBatchDeleteAlert = false
    @State private var composeSeed: ComposeSeed?
    @State private var snoozePickerMail: MailItem?

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
                if vm.showGroupedSections {
                    ForEach(vm.groupedSections) { section in
                        Section(section.title) {
                            ForEach(section.mails) { mail in
                                if vm.isSelecting {
                                    selectableRow(mail)
                                } else {
                                    normalRow(mail)
                                }
                            }
                        }
                    }
                } else {
                    ForEach(vm.displayedMails) { mail in
                        if vm.isSelecting {
                            selectableRow(mail)
                        } else {
                            normalRow(mail)
                        }
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
            .sheet(item: $snoozePickerMail) { mail in
                SnoozeDatePickerSheet { date in
                    vm.snooze(mail, until: date)
                }
            }
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
            .onAppear {
                Task { await vm.reload() }
                // Возврат из письма: onDisappear остановил polling — возобновляем.
                vm.startPolling()
            }
            .onDisappear { vm.stopPolling() }
            .onChange(of: vm.searchScope) { _ in
                Task { await vm.reload() }
            }
            .onChange(of: scenePhase) { phase in
                vm.isAppActive = phase == .active
                if phase == .active {
                    vm.startPolling()
                } else if phase == .background {
                    // С keep-alive процесс жив и в фоне — polling продолжает
                    // проверять почту и постит локальные уведомления.
                    if !Prefs.keepaliveEnabled { vm.stopPolling() }
                }
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
            .sheet(isPresented: $showStats) {
                MailStatsView()
            }
            .alert("Удалить письма?", isPresented: $showBatchDeleteAlert) {
                Button("Удалить", role: .destructive) { vm.batchDelete() }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Выбранные письма будут удалены безвозвратно: \(vm.selectedIds.count)")
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
    /// Отступы строк по настройке «list_density».
    private var rowInsets: EdgeInsets {
        switch Prefs.listDensity {
        case .compact: return EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 12)
        case .regular: return EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 12)
        case .spacious: return EdgeInsets(top: 11, leading: 16, bottom: 11, trailing: 12)
        }
    }

    private func normalRow(_ mail: MailItem) -> some View {
        NavigationLink {
            MailReaderView(mailId: mail.id,
                           siblingIds: vm.displayedMails.map(\.id)) { Task { await vm.reload() } }
        } label: {
            MailRowView(state: MailRowState(mail: mail))
        }
        .listRowInsets(rowInsets)
        .contextMenu {
            if vm.currentFolder == snoozedFolderId {
                Button {
                    vm.unsnooze(mail)
                } label: {
                    Label("Вернуть в папку", systemImage: "clock.arrow.circlepath")
                }
                Divider()
            }

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

            if vm.currentFolder != snoozedFolderId {
                Menu {
                    ForEach(SnoozePreset.allCases) { preset in
                        Button {
                            vm.snooze(mail, until: preset.date())
                        } label: {
                            Label(preset.title, systemImage: preset.systemImage)
                        }
                    }
                    Divider()
                    Button {
                        snoozePickerMail = mail
                    } label: {
                        Label("Своё время…", systemImage: "calendar.badge.clock")
                    }
                } label: {
                    Label("Отложить", systemImage: "clock")
                }

                Button {
                    vm.blockSender(mail)
                } label: {
                    Label("Заблокировать отправителя", systemImage: "person.slash")
                }
            }

            Divider()

            Button {
                Haptics.light()
                PinnedMailStore.toggle(mail.id)
                Task { await vm.reload() }
            } label: {
                Label(
                    PinnedMailStore.isPinned(mail.id) ? "Открепить" : "Закрепить",
                    systemImage: PinnedMailStore.isPinned(mail.id) ? "pin.slash" : "pin"
                )
            }

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
            swipeButton(Prefs.swipeTrailing, mail: mail)
            if Prefs.swipeTrailing != .delete {
                Button(role: .destructive) {
                    Haptics.warning()
                    vm.delete(mail)
                } label: {
                    Label("Удалить", systemImage: "trash")
                }
            }
            if Prefs.swipeTrailing != .spam {
                Button {
                    Haptics.medium()
                    vm.moveToSpam(mail)
                } label: {
                    Label("Спам", systemImage: "exclamationmark.octagon")
                }.tint(.red)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            swipeButton(Prefs.swipeLeading, mail: mail)
            if Prefs.swipeLeading != .read {
                Button {
                    Haptics.light()
                    vm.setRead(mail, !mail.read)
                } label: {
                    Label(mail.read ? "Не прочитано" : "Прочитано",
                          systemImage: mail.read ? "envelope.badge" : "envelope.open")
                }.tint(.indigo)
            }
            if Prefs.swipeLeading != .copy {
                Button {
                    Haptics.medium()
                    let emailToCopy = mail.fromEmail.isEmpty ? mail.sender : mail.fromEmail
                    ClipboardManager.shared.copySecurely(text: emailToCopy)
                } label: {
                    Label("Копировать email", systemImage: "doc.on.doc")
                }.tint(.blue)
            }
        }
        .onAppear {
            if mail.id == vm.displayedMails.last?.id {
                Task { await vm.loadMore() }
            }
        }
    }

    /// Кнопка свайпа по настройке: назначаемое действие полного свайпа.
    @ViewBuilder
    private func swipeButton(_ kind: SwipeActionKind, mail: MailItem) -> some View {
        switch kind {
        case .trash:
            Button {
                Haptics.medium()
                vm.moveToTrash(mail)
            } label: {
                Label("В корзину", systemImage: "trash")
            }
            .tint(.orange)
        case .delete:
            Button(role: .destructive) {
                Haptics.warning()
                vm.delete(mail)
            } label: {
                Label("Удалить", systemImage: "trash")
            }
        case .read:
            Button {
                Haptics.light()
                vm.setRead(mail, !mail.read)
            } label: {
                Label(mail.read ? "Не прочитано" : "Прочитано",
                      systemImage: mail.read ? "envelope.badge" : "envelope.open")
            }
            .tint(.indigo)
        case .snooze:
            Button {
                snoozePickerMail = mail
            } label: {
                Label("Отложить…", systemImage: "clock")
            }
            .tint(.teal)
        case .spam:
            Button {
                Haptics.medium()
                vm.moveToSpam(mail)
            } label: {
                Label("Спам", systemImage: "exclamationmark.octagon")
            }
            .tint(.red)
        case .copy:
            Button {
                Haptics.medium()
                let emailToCopy = mail.fromEmail.isEmpty ? mail.sender : mail.fromEmail
                ClipboardManager.shared.copySecurely(text: emailToCopy)
            } label: {
                Label("Копировать email", systemImage: "doc.on.doc")
            }
            .tint(.blue)
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
        .listRowInsets(rowInsets)
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
                Haptics.warning()
                showBatchDeleteAlert = true
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
                chip("Важные", active: vm.currentFolder == "important",
                     badge: vm.importantUnread > 0 && vm.currentFolder != "important" ? vm.importantUnread : nil) {
                    Haptics.light()
                    vm.selectFolder("important")
                }
                chip("С вложениями", active: vm.filterAttachments) {
                    Haptics.light()
                    vm.filterAttachments.toggle()
                }
                chip("Отложенные", active: vm.currentFolder == snoozedFolderId,
                     badge: vm.snoozedCount > 0 && vm.currentFolder != snoozedFolderId ? vm.snoozedCount : nil) {
                    Haptics.light()
                    vm.selectFolder(snoozedFolderId)
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
                Haptics.light()
                showStats = true
            } label: {
                Label("Статистика почты", systemImage: "chart.bar.xaxis")
            }

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
        EmptyStateView(
            icon: emptyIcon,
            title: emptyTitle,
            subtitle: emptySubtitle,
            actionTitle: vm.searchQuery.isEmpty ? "Обновить" : nil,
            action: { Task { await vm.refresh() } })
    }

    private var emptyIcon: String {
        if !vm.searchQuery.isEmpty { return "magnifyingglass" }
        if vm.currentFolder == snoozedFolderId { return "clock" }
        return "envelope.open"
    }

    private var emptyTitle: String {
        if !vm.searchQuery.isEmpty { return "Ничего не найдено" }
        if vm.currentFolder == snoozedFolderId { return "Нет отложенных писем" }
        if vm.filterUnreadOnly { return "Нет непрочитанных писем" }
        return "В этой папке пусто"
    }

    private var emptySubtitle: String? {
        if !vm.searchQuery.isEmpty {
            return "Попробуйте изменить запрос или область поиска"
        }
        if vm.currentFolder == snoozedFolderId {
            return "Отложенные письма спрятаны из списков и вернутся в выбранное время"
        }
        return nil
    }
}

// MARK: - Shared Views

struct AccountSwitcherView: View {
    @ObservedObject var accounts: AccountStore
    @Environment(\.dismiss) private var dismiss
    @State private var showSettings = false
    @State private var showAddAccount = false
    @State private var accountPendingRemoval: String?

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
                                accountPendingRemoval = email
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
            .alert("Удалить аккаунт?", isPresented: Binding(
                get: { accountPendingRemoval != nil },
                set: { if !$0 { accountPendingRemoval = nil } }
            )) {
                Button("Удалить", role: .destructive) {
                    if let email = accountPendingRemoval {
                        Task { await accounts.remove(email) }
                    }
                    accountPendingRemoval = nil
                }
                Button("Отмена", role: .cancel) { accountPendingRemoval = nil }
            } message: {
                Text("Аккаунт \(accountPendingRemoval ?? "") будет удалён с устройства вместе с локальным кэшем. При необходимости войдите заново.")
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