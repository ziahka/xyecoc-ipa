import Foundation

actor MailDatabase {
    static let shared = MailDatabase()

    // MARK: - In-memory state

    private var mailsById: [Int64: MailItem] = [:]
    private var folderList: [Folder] = []
    private var tagList: [Tag] = []

    // MARK: - Persistence

    private struct Snapshot: Codable {
        var mails: [MailItem]
        var folders: [Folder]
        var tags: [Tag]
    }

    private let appDir: URL
    private var activeAccount: String

    private var cacheURL: URL {
        appDir.appendingPathComponent("cache-\(Self.sanitize(activeAccount)).json")
    }

    private static func sanitize(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let scalars = s.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let name = String(scalars)
        return name.isEmpty ? "default" : name
    }

    init() {
        let dir = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        let appDir = dir.appendingPathComponent("XyecocMail", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        self.appDir = appDir
        let account = KeychainManager.shared.activeEmail() ?? "default"
        self.activeAccount = account

        let targetURL = appDir.appendingPathComponent("cache-\(Self.sanitize(account)).json")
        if let data = try? Data(contentsOf: targetURL),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            self.mailsById = Dictionary(snapshot.mails.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
            self.folderList = snapshot.folders
            self.tagList = snapshot.tags
        }

        // Load HTML body cache
        let htmlURL = appDir.appendingPathComponent("html-cache-\(Self.sanitize(account)).json")
        if let hData = try? Data(contentsOf: htmlURL),
           let dict = try? JSONDecoder().decode([String: String].self, from: hData) {
            self.htmlCache = Dictionary(uniqueKeysWithValues: dict.compactMap { k, v in
                guard let id = Int64(k) else { return nil }
                return (id, v)
            })
        }

        snoozes = Self.readSnoozes(url: appDir.appendingPathComponent("snooze-\(Self.sanitize(account)).json"))
    }

    // MARK: - Per-account switching

    func activate(account: String) {
        guard account != activeAccount else { return }
        activeAccount = account
        mailsById.removeAll()
        folderList.removeAll()
        tagList.removeAll()
        htmlCache.removeAll()
        snoozes.removeAll()
        load()
        snoozes = Self.readSnoozes(url: snoozeURL)
    }

    func deleteCache(forAccount account: String) {
        let url = appDir.appendingPathComponent("cache-\(Self.sanitize(account)).json")
        try? FileManager.default.removeItem(at: url)
        let hUrl = appDir.appendingPathComponent("html-cache-\(Self.sanitize(account)).json")
        try? FileManager.default.removeItem(at: hUrl)
        let sUrl = appDir.appendingPathComponent("snooze-\(Self.sanitize(account)).json")
        try? FileManager.default.removeItem(at: sUrl)
        if account == activeAccount {
            mailsById.removeAll()
            folderList.removeAll()
            tagList.removeAll()
            htmlCache.removeAll()
            snoozes.removeAll()
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: cacheURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        mailsById = Dictionary(snapshot.mails.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        folderList = snapshot.folders
        tagList = snapshot.tags
        loadHtmlCache()
    }

    /// Coalesces snapshot writes: mutations arriving in a burst are flushed
    /// once, 400 ms after the last call, instead of encoding and rewriting
    /// the whole cache on every single mutation.
    private var persistTask: Task<Void, Never>?

    private func persist() {
        persistTask?.cancel()
        persistTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            writeSnapshotNow()
        }
    }

    private func writeSnapshotNow() {
        let snapshot = Snapshot(mails: Array(mailsById.values),
                                folders: folderList, tags: tagList)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }

    // MARK: - MailDao

    func mails(folder: String) -> [MailItem] {
        mailsById.values
            .filter { $0.folder == folder }
            .sorted { $0.id > $1.id }
    }

    func mail(id: Int64) -> MailItem? { mailsById[id] }

    /// Every cached mail of the active account, newest first. Feeds the
    /// local statistics screen without any network round-trip.
    func allMails() -> [MailItem] {
        mailsById.values.sorted { $0.id > $1.id }
    }

    func upsertMails(_ mails: [MailItem]) {
        for mail in mails { mailsById[mail.id] = mail }
        persist()
    }

    func setRead(_ id: Int64, _ read: Bool) {
        guard var m = mailsById[id] else { return }
        m.read = read
        mailsById[id] = m
        persist()
    }

    func setImportant(_ id: Int64, _ important: Bool) {
        guard var m = mailsById[id] else { return }
        m.important = important
        mailsById[id] = m
        persist()
    }

    func move(_ id: Int64, toFolder folder: String) {
        guard var m = mailsById[id] else { return }
        m.folder = folder
        mailsById[id] = m
        persist()
    }

    func delete(_ id: Int64) {
        mailsById[id] = nil
        if snoozes[id] != nil {
            snoozes[id] = nil
            persistSnoozesNow()
        }
        persist()
    }

    func delete(ids: [Int64]) {
        var snoozeChanged = false
        for id in ids {
            mailsById[id] = nil
            if snoozes[id] != nil {
                snoozes[id] = nil
                snoozeChanged = true
            }
        }
        if snoozeChanged { persistSnoozesNow() }
        persist()
    }

    func clearFolder(_ folder: String) {
        let removedIds = Set(mailsById.filter { $0.value.folder == folder }.keys)
        let droppedSnoozes = removedIds.filter { snoozes[$0] != nil }
        if !droppedSnoozes.isEmpty {
            for id in droppedSnoozes { snoozes[id] = nil }
            persistSnoozesNow()
        }
        mailsById = mailsById.filter { $0.value.folder != folder }
        persist()
    }

    func unreadCount(folder: String) -> Int {
        mailsById.values.filter { $0.folder == folder && !$0.read }.count
    }

    func pruneNotInList(folder: String, minId: Int64, fetchedIds: [Int64]) {
        let keep = Set(fetchedIds)
        mailsById = mailsById.filter { _, m in
            !(m.folder == folder && m.id >= minId && !keep.contains(m.id))
        }
        persist()
    }

    func pruneNotInListRange(folder: String, minId: Int64, maxId: Int64, fetchedIds: [Int64]) {
        let keep = Set(fetchedIds)
        mailsById = mailsById.filter { _, m in
            !(m.folder == folder && m.id >= minId && m.id <= maxId && !keep.contains(m.id))
        }
        persist()
    }

    // MARK: - FolderDao

    func folders() -> [Folder] { folderList.sorted { $0.name < $1.name } }

    func upsertFolders(_ folders: [Folder]) {
        for f in folders {
            if let idx = folderList.firstIndex(where: { $0.id == f.id }) {
                folderList[idx] = f
            } else {
                folderList.append(f)
            }
        }
        persist()
    }

    func replaceFolders(_ folders: [Folder]) { folderList = folders; persist() }
    func deleteFolder(id: Int64) { folderList.removeAll { $0.id == id }; persist() }
    func clearFolders() { folderList.removeAll(); persist() }

    // MARK: - TagDao

    func tags() -> [Tag] { tagList.sorted { $0.name < $1.name } }

    func upsertTags(_ tags: [Tag]) {
        for t in tags {
            if let idx = tagList.firstIndex(where: { $0.id == t.id }) {
                tagList[idx] = t
            } else {
                tagList.append(t)
            }
        }
        persist()
    }

    func replaceTags(_ tags: [Tag]) { tagList = tags; persist() }
    func deleteTag(id: Int64) { tagList.removeAll { $0.id == id }; persist() }
    func clearTags() { tagList.removeAll(); persist() }

    // MARK: - Snooze (local only)

    /// One snoozed mail: the cached item plus the moment it comes back.
    struct SnoozedMail {
        let mail: MailItem
        let until: Date
    }

    private struct SnoozeEntry: Codable {
        var id: Int64
        var until: Date
    }

    private var snoozes: [Int64: Date] = [:]

    private var snoozeURL: URL {
        appDir.appendingPathComponent("snooze-\(Self.sanitize(activeAccount)).json")
    }

    /// Static-члены актора не изолированы — так метод можно звать из init.
    private static func readSnoozes(url: URL) -> [Int64: Date] {
        guard let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([SnoozeEntry].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.until) })
    }

    private func persistSnoozesNow() {
        let entries = snoozes.map { SnoozeEntry(id: $0.key, until: $0.value) }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: snoozeURL, options: .atomic)
    }

    func snooze(mailId: Int64, until date: Date) {
        snoozes[mailId] = date
        persistSnoozesNow()
    }

    func unsnooze(mailId: Int64) {
        guard snoozes[mailId] != nil else { return }
        snoozes[mailId] = nil
        persistSnoozesNow()
    }

    /// Mail ids hidden by an active snooze right now.
    func activeSnoozeIds() -> Set<Int64> {
        let now = Date()
        return Set(snoozes.filter { $0.value > now }.keys)
    }

    func activeSnoozeCount() -> Int { snoozedMails().count }

    /// Snoozed mails that have not woken up yet, soonest first.
    /// Осиротевшие записи (письмо удалено/вычищено из кэша) убираем сразу.
    func snoozedMails() -> [SnoozedMail] {
        let now = Date()
        var changed = false
        var result: [SnoozedMail] = []
        for (id, until) in snoozes.sorted(by: { $0.value < $1.value }) {
            guard until > now else { continue }
            if let mail = mailsById[id] {
                result.append(SnoozedMail(mail: mail, until: until))
            } else {
                snoozes[id] = nil
                changed = true
            }
        }
        if changed { persistSnoozesNow() }
        return result
    }

    // MARK: - New-mail detection (polling toast)

    func maxMailId() -> Int64 { mailsById.keys.max() ?? 0 }

    /// Сколько писем новее заданного id; ограничение по папке — чтобы
    /// собственные отправки и черновики не считались «новыми письмами».
    func countNewer(than id: Int64, inFolder folder: String? = nil) -> Int {
        guard id > 0 else { return 0 }
        return mailsById.values.filter { $0.id > id && (folder == nil || $0.folder == folder) }.count
    }

    func unreadCountAll() -> Int { mailsById.values.filter { !$0.read }.count }

    // MARK: - HTML body cache

    private var htmlCache: [Int64: String] = [:]

    func cachedHtml(mailId: Int64) -> String? { htmlCache[mailId] }

    func cacheHtml(mailId: Int64, html: String) {
        guard !html.isEmpty else { return }
        htmlCache[mailId] = html
        persistHtml()
    }

    private var htmlCacheURL: URL {
        appDir.appendingPathComponent("html-cache-\(Self.sanitize(activeAccount)).json")
    }

    private func loadHtmlCache() {
        guard let data = try? Data(contentsOf: htmlCacheURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return }
        htmlCache = Dictionary(uniqueKeysWithValues: dict.compactMap { k, v in
            guard let id = Int64(k) else { return nil }
            return (id, v)
        })
    }

    /// HTML bodies are the largest payloads, so their cache writes are
    /// coalesced with a longer window (1 s).
    private var persistHtmlTask: Task<Void, Never>?

    private func persistHtml() {
        persistHtmlTask?.cancel()
        persistHtmlTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            writeHtmlCacheNow()
        }
    }

    private func writeHtmlCacheNow() {
        let dict = Dictionary(uniqueKeysWithValues: htmlCache.map { (String($0.key), $0.value) })
        guard let data = try? JSONEncoder().encode(dict) else { return }
        try? data.write(to: htmlCacheURL, options: .atomic)
    }

    // MARK: - Cache size

    func totalCacheSizeBytes() -> Int {
        var total = 0
        for url in [cacheURL, htmlCacheURL] {
            total += (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        }
        return total
    }

    // MARK: - Global

    func clearAll() {
        mailsById.removeAll()
        folderList.removeAll()
        tagList.removeAll()
        htmlCache.removeAll()
        snoozes.removeAll()
        // Отложенные записи здесь не подходят: файлы должны опустеть сразу.
        persistTask?.cancel()
        persistHtmlTask?.cancel()
        writeSnapshotNow()
        writeHtmlCacheNow()
        persistSnoozesNow()
    }
}
