//
//  MailDatabase.swift
//  XyecocMail
//
//  Offline-first local cache — the iOS analogue of Room (`AppDatabase` + DAOs).
//  Implemented as an `actor` over Codable in-memory collections persisted to a
//  single JSON snapshot on disk. No external SPM dependency (no GRDB/SQLite
//  ceremony); the actor gives race-free access from the async repository.
//
//  Room parity notes:
//   - Mails are keyed globally by `id` (Room's @PrimaryKey), `folder` is a
//     column, so moving folders and cross-folder dedupe work as in Room.
//   - `pruneNotInList` / `pruneNotInListRange` reproduce the two diff-delete
//     queries used by `MailRepository.fetchMails` to drop stale rows.
//   - Reads return sorted snapshots matching the DAO `ORDER BY` clauses
//     (mails: id DESC; folders/tags: name ASC).
//

import Foundation

actor MailDatabase {

    static let shared = MailDatabase()

    // MARK: - In-memory state (mirrors the Room tables)

    private var mailsById: [Int64: MailItem] = [:]
    private var folderList: [Folder] = []
    private var tagList: [Tag] = []

    // MARK: - Persistence

    private struct Snapshot: Codable {
        var mails: [MailItem]
        var folders: [Folder]
        var tags: [Tag]
    }

    private let cacheURL: URL

    init() {
        let dir = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        let appDir = dir.appendingPathComponent("XyecocMail", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        self.cacheURL = appDir.appendingPathComponent("cache.json")
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: cacheURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        mailsById = Dictionary(uniqueKeysWithValues: snapshot.mails.map { ($0.id, $0) })
        folderList = snapshot.folders
        tagList = snapshot.tags
    }

    private func persist() {
        let snapshot = Snapshot(mails: Array(mailsById.values),
                                folders: folderList, tags: tagList)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }

    // MARK: - MailDao

    /// SELECT * FROM mails WHERE folder = ? ORDER BY id DESC
    func mails(folder: String) -> [MailItem] {
        mailsById.values
            .filter { $0.folder == folder }
            .sorted { $0.id > $1.id }
    }

    func mail(id: Int64) -> MailItem? { mailsById[id] }

    /// @Insert(onConflict = REPLACE)
    func upsertMails(_ mails: [MailItem]) {
        for mail in mails { mailsById[mail.id] = mail }
        persist()
    }

    func setRead(_ id: Int64, _ read: Bool) {
        guard var m = mailsById[id] else { return }
        m.read = read; mailsById[id] = m; persist()
    }

    func setImportant(_ id: Int64, _ important: Bool) {
        guard var m = mailsById[id] else { return }
        m.important = important; mailsById[id] = m; persist()
    }

    func move(_ id: Int64, toFolder folder: String) {
        guard var m = mailsById[id] else { return }
        m.folder = folder; mailsById[id] = m; persist()
    }

    func delete(_ id: Int64) { mailsById[id] = nil; persist() }

    func delete(ids: [Int64]) {
        for id in ids { mailsById[id] = nil }
        persist()
    }

    /// DELETE FROM mails WHERE folder = ?
    func clearFolder(_ folder: String) {
        mailsById = mailsById.filter { $0.value.folder != folder }
        persist()
    }

    /// SELECT COUNT(*) FROM mails WHERE folder = ? AND read = 0
    func unreadCount(folder: String) -> Int {
        mailsById.values.filter { $0.folder == folder && !$0.read }.count
    }

    /// DELETE FROM mails WHERE folder = ? AND id >= :minId AND id NOT IN (:fetchedIds)
    func pruneNotInList(folder: String, minId: Int64, fetchedIds: [Int64]) {
        let keep = Set(fetchedIds)
        mailsById = mailsById.filter { _, m in
            !(m.folder == folder && m.id >= minId && !keep.contains(m.id))
        }
        persist()
    }

    /// DELETE FROM mails WHERE folder = ? AND id >= :minId AND id <= :maxId AND id NOT IN (:fetchedIds)
    func pruneNotInListRange(folder: String, minId: Int64, maxId: Int64, fetchedIds: [Int64]) {
        let keep = Set(fetchedIds)
        mailsById = mailsById.filter { _, m in
            !(m.folder == folder && m.id >= minId && m.id <= maxId && !keep.contains(m.id))
        }
        persist()
    }

    // MARK: - FolderDao

    /// SELECT * FROM folders ORDER BY name ASC
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

    /// SELECT * FROM tags ORDER BY name ASC
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

    // MARK: - Global

    /// db.clearAllTables() — called on login/logout for a fresh account.
    func clearAll() {
        mailsById.removeAll()
        folderList.removeAll()
        tagList.removeAll()
        persist()
    }
}
