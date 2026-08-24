@MainActor
final class ReaderViewModel: ObservableObject {
    @Published var details: MailDetails?
    @Published var bodyHtml: String = ""
    @Published var isLoading = false
    @Published var isQuickReplying = false
    @Published var quickReplyText = ""
    @Published var errorMessage: String?

    private let mailRepo = MailRepository()
    private let settingsRepo = SettingsRepository()
    private let mailId: Int64

    init(mailId: Int64) {
        self.mailId = mailId
    }

    func loadMail() async {
        isLoading = true
        defer { isLoading = false }

        let resp = await mailRepo.fetchMailDetails(id: mailId)
        if let data = resp.mailDetails() {
            self.details = data
            self.bodyHtml = data.message ?? "<p>\(data.snippet ?? "")</p>"
        }
    }

    func sendQuickReply() async -> Bool {
        let trimmed = quickReplyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let mail = details else { return false }

        let recipient = mail.fromEmail.isEmpty ? mail.sender : mail.fromEmail
        guard !recipient.isEmpty else {
            errorMessage = "Не удалось определить адрес получателя"
            return false
        }

        let baseSubject = mail.subject ?? "Без темы"
        let replySubject = baseSubject.lowercased().hasPrefix("re:") ? baseSubject : "Re: \(baseSubject)"

        isQuickReplying = true
        defer { isQuickReplying = false }

        var fullMessage = trimmed
        if let profile = await settingsRepo.getProfile(),
           let sig = profile.signature, !sig.isEmpty {
            fullMessage = "\(fullMessage)<br><br>\(sig)"
        }

        let resp = await mailRepo.sendMail(
            recipients: [recipient],
            subject: replySubject,
            messageHtml: fullMessage,
            attachments: [],
            isDraft: false
        )

        if resp.isSuccess() {
            quickReplyText = ""
            Haptics.success()
            return true
        } else {
            Haptics.error()
            errorMessage = resp.message ?? "Не удалось отправить ответ"
            return false
        }
    }
}