import SwiftUI
import Combine

@MainActor
final class ReaderViewModel: ObservableObject {
    @Published var details: MailDetails?
    @Published var html: String = ""
    @Published var isLoading = false
    @Published var isQuickReplying = false
    @Published var quickReplyText = ""
    @Published var errorMessage: String?
    @Published var folders: [Folder] = []
    @Published var tags: [Tag] = []

    private let repo = MailRepository()
    private let settingsRepo = SettingsRepository()
    private let db = MailDatabase.shared

    func load(mailId: Int64) async {
        isLoading = true
        folders = await db.folders()
        tags = await db.tags()

        let response = await repo.fetchMailDetails(mailId: mailId)
        if let d = response.mailDetails() {
            details = d
            let body = await repo.fetchMailBodyHtml(mailId: mailId)
            if !body.isEmpty {
                html = body
            } else if let message = d.message, !message.isEmpty {
                html = message
            } else {
                html = "<p style=\"font-family:sans-serif;font-size:16px;color:#333;line-height:1.5;\">\(d.snippet ?? "")</p>"
            }
            await db.setRead(mailId, true)
        }
        isLoading = false
    }

    func sendQuickReply() async -> Bool {
        let trimmed = quickReplyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let mail = details else { return false }

        let recipient = (mail.fromEmail?.isEmpty == false) ? mail.fromEmail! : mail.sender
        guard !recipient.isEmpty else {
            errorMessage = "Не удалось определить адрес получателя"
            return false
        }

        let baseSubject = mail.getDisplaySubjectSafe()
        let replySubject = baseSubject.lowercased().hasPrefix("re:") ? baseSubject : "Re: \(baseSubject)"

        isQuickReplying = true
        defer { isQuickReplying = false }

        var fullMessage = trimmed
        let respProfile = await settingsRepo.getProfile()
        if respProfile.isSuccess(),
           let profile = respProfile.decodeData(as: UserAccount.self),
           !profile.signature.isEmpty {
            fullMessage = "\(fullMessage)<br><br>\(profile.signature)"
        }

        let resp = await repo.sendMail(
            recipients: [recipient],
            subject: replySubject,
            messageHtml: fullMessage,
            attachments: [],
            isDraft: false
        )

        if resp.isSuccess() {
            quickReplyText = ""
            return true
        } else {
            errorMessage = resp.message ?? "Не удалось отправить ответ"
            return false
        }
    }

    func deleteCurrent() async {
        guard let id = details?.id else { return }
        let folder = await db.mail(id: id)?.folder
        _ = await repo.performMailAction(mailId: id, action: "delete", folder: folder)
    }

    func markImportant() async {
        guard let id = details?.id else { return }
        _ = await repo.performMailAction(mailId: id, action: "important")
    }

    func move(toFolderId folderId: Int64) async {
        guard let id = details?.id else { return }
        _ = await repo.performMailAction(mailId: id, action: "move-to-folder", value: .int(folderId))
    }

    func blockSender() async {
        guard let id = details?.id else { return }
        _ = await repo.blockSender(mailId: id)
    }

    func report(_ type: String) async {
        guard let id = details?.id else { return }
        _ = await repo.reportViolation(mailId: id, type: type)
    }
}
