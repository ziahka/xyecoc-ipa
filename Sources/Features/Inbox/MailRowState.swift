import SwiftUI

struct MailRowState: Identifiable, Equatable {
    let id: Int64
    let sender: String
    let email: String
    let subject: String
    let snippet: String
    let formattedDate: String
    let isRead: Bool
    let isImportant: Bool
    let hasAttachments: Bool
    let tagName: String?
    let tagColorHex: String?

    init(mail: MailItem) {
        self.id = mail.id
        self.sender = mail.displayName()
        self.email = !mail.fromEmail.isEmpty ? mail.fromEmail : mail.sender
        self.subject = mail.displaySubject()
        self.snippet = mail.snippet
        self.formattedDate = DateUtils.formatDateRelative(mail.createdAt)
        self.isRead = mail.read
        self.isImportant = mail.important
        self.hasAttachments = mail.hasAttachments
        self.tagName = mail.tagName
        self.tagColorHex = mail.tagColor
    }
}