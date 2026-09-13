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
    }

    // MARK: - Per-account switching

    func activate(account: String) {
        guard account != activeAccount else { return }
        activeAccount = account
        mailsById.removeAll()
        folderList.removeAll()
        tagList.removeAll()
        htmlCache.removeAll()
        load()
    }

    func deleteCache(forAccount account: String) {
        let url = appDir.appendingPathComponent("cache-\(Self.sanitize(account)).json")
        try? FileManager.default.removeItem(at: url)
        let hUrl = appDir.appendingPathComponent("html-cache-\(Self.sanitize(account)).json")
        try? FileManager.default.removeItem(at: hUrl)
        if account == activeAccount {
            mailsById.removeAll()
            folderList.removeAll()
            tagList.removeAll()
            htmlCache.removeAll()
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

    private func persist() {
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
        persist()
    }

    func delete(ids: [Int64]) {
        for id in ids { mailsById[id] = nil }
        persist()
    }

    func clearFolder(_ folder: String) {
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

    private func persistHtml() {
        let dict = Dictionary(uniqueKeysWithValues: htmlCache.map { (String($0.key), $0.value) })
        guard let data = try? JSONEncoder().encode(dict) else { return }
        try? data.write(to: htmlCacheURL, options: .atomic)
    }

    // MARK: - Global

    func clearAll() {
        mailsById.removeAll()
        folderList.removeAll()
        tagList.removeAll()
        htmlCache.removeAll()
        persist()
        persistHtml()
    }
}
