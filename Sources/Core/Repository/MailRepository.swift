//
//  MailRepository.swift
//  XyecocMail
//
//  Port of Kotlin `MailRepository` (data/repository/Repositories.kt).
//  Builds the `mail`-service RPC payloads, writes results into `MailDatabase`,
//  and reproduces the offline-first diff-prune reconciliation from `fetchMails`.
//
//  All methods are async; network runs on the cooperative pool via the
//  nonisolated `ApiClient`, DB writes hop onto the `MailDatabase` actor.
//

import Foundation

final class MailRepository {

    private let api: ApiClient
    private let db: MailDatabase
    private let keychain: KeychainManager

    init(api: ApiClient = .shared,
         db: MailDatabase = .shared,
         keychain: KeychainManager = .shared) {
        self.api = api
        self.db = db
        self.keychain = keychain
    }

    private var token: String { keychain.getToken() ?? "" }

    // MARK: - Local reads (snapshots from the cache)

    func localMails(folder: String) async -> [MailItem] { await db.mails(folder: folder) }
    func localFolders() async -> [Folder] { await db.folders() }
    func localTags() async -> [Tag] { await db.tags() }

    // MARK: - mail/default (list + pagination + folder/tag sync)

    func fetchMails(folder: String = "inbox",
                    searchText: String? = nil,
                    page: Int = 1,
                    lastMailId: Int64 = 0) async -> ApiResponse {
        let payload = RequestPayload(
            service: "mail",
            action: "default",
            token: token,
            params: .object(["param_1": .string(folder)]),
            searchText: searchText,
            lastMailId: lastMailId,
            page: page
        )
        let response = await api.request(payload)

        guard response.error == nil else { return response }

        if let mails = response.mails {
            // Stamp the folder onto each row (Room did `it.copy(folder = folder)`).
            let stamped = mails.map { row -> MailItem in
                var m = row; m.folder = folder; return m
            }
            await db.upsertMails(stamped)

            if (searchText ?? "").isEmpty {
                if mails.isEmpty {
                    if page == 1 && lastMailId == 0 {
                        await db.clearFolder(folder)
                    }
                } else {
                    let fetchedIds = mails.map { $0.id }
                    let minId: Int64 = (page == 1 && mails.count < 20)
                        ? 0
                        : (fetchedIds.min() ?? 0)
                    if page == 1 && lastMailId == 0 {
                        await db.pruneNotInList(folder: folder, minId: minId, fetchedIds: fetchedIds)
                    } else {
                        let maxId = fetchedIds.max() ?? Int64.max
                        await db.pruneNotInListRange(folder: folder, minId: minId,
                                                     maxId: maxId, fetchedIds: fetchedIds)
                    }
                }
            }
        }

        if let folders = response.folders { await db.upsertFolders(folders) }
        if let tags = response.tags { await db.upsertTags(tags) }
        return response
    }

    // MARK: - mail/view (details)

    func fetchMailDetails(mailId: Int64) async -> ApiResponse {
        let payload = RequestPayload(
            service: "mail",
            action: "view",
            token: token,
            params: .object(["param_1": .string(String(mailId)), "mail_id": .int(mailId)])
        )
        return await api.request(payload)
    }

    /// Rendered HTML body from the CDN (delegates to `ApiClient`).
    func fetchMailBodyHtml(mailId: Int64) async -> String {
        await api.fetchMailBodyHtml(mailId: mailId, token: token)
    }

    // MARK: - mail/mail-action (read, delete, important, move)

    func performMailAction(mailId: Int64,
                           action: String,
                           value: JSONValue? = nil,
                           folder: String? = nil) async -> ApiResponse {
        let payload = RequestPayload(
            service: "mail",
            action: "mail-action",
            token: token,
            data: .object([
                "id": .int(mailId),
                "action": .string(action),
                "value": value ?? .null
            ]),
            pageId: folder.map { "/\($0)/" }
        )
        let response = await api.request(payload)
        if response.error == nil {
            switch action {
            case "read": await db.setRead(mailId, true)
            case "delete": await db.delete(mailId)
            case "important": await db.setImportant(mailId, true)
            case "move-to-folder":
                if let name = value?.stringValue { await db.move(mailId, toFolder: name) }
            default: break
            }
        }
        return response
    }

    /// Mark read/unread. Android only exposes "read"; we pass a boolean `value`
    /// so the same endpoint also supports marking unread from a swipe action.
    func setReadStatus(mailId: Int64, read: Bool, folder: String? = nil) async -> ApiResponse {
        let payload = RequestPayload(
            service: "mail",
            action: "mail-action",
            token: token,
            data: .object([
                "id": .int(mailId),
                "action": .string("read"),
                "value": .bool(read)
            ]),
            pageId: folder.map { "/\($0)/" }
        )
        let response = await api.request(payload)
        if response.error == nil { await db.setRead(mailId, read) }
        return response
    }

    func batchDeleteMails(mailIds: [Int64], folder: String? = nil) async -> ApiResponse {
        let idsStr = mailIds.map { String($0) }.joined(separator: ",")
        let payload = RequestPayload(
            service: "mail",
            action: "mail-action",
            token: token,
            data: .object([
                "id": .string(idsStr),
                "action": .string("delete"),
                "value": .null
            ]),
            pageId: folder.map { "/\($0)/" }
        )
        let response = await api.request(payload)
        if response.error == nil { await db.delete(ids: mailIds) }
        return response
    }

    func markAllRead() async -> ApiResponse {
        let payload = RequestPayload(service: "mail", action: "read-all", token: token)
        return await api.request(payload)
    }

    func reportViolation(mailId: Int64, type: String) async -> ApiResponse {
        let payload = RequestPayload(
            service: "mail",
            action: "mail-action",
            token: token,
            data: .object(["id": .int(mailId), "action": .string("violation"), "value": .string(type)])
        )
        return await api.request(payload)
    }

    func blockSender(mailId: Int64) async -> ApiResponse {
        let payload = RequestPayload(
            service: "mail",
            action: "mail-action",
            token: token,
            data: .object(["id": .int(mailId), "action": .string("block"), "value": .null])
        )
        return await api.request(payload)
    }

    // MARK: - mail/message-new (send) — used by Compose (later milestone)

    func sendMail(recipients: [String],
                  subject: String,
                  messageHtml: String,
                  attachments: [Attachment] = [],
                  isDraft: Bool = false) async -> ApiResponse {
        let mapped: [JSONValue] = attachments.map {
            .object(["filename": .string($0.fileName),
                     "content": $0.content.map { JSONValue.string($0) } ?? .null])
        }
        let payload = RequestPayload(
            service: "mail",
            action: "message-new",
            token: token,
            data: .object([
                "users": .string(recipients.joined(separator: ",")),
                "subject": .string(subject),
                "message": .string(messageHtml),
                "attaches": .array(mapped)
            ]),
            draft: isDraft
        )
        return await api.request(payload)
    }
}
