import SwiftUI

struct MailRowState: Identifiable, Equatable {
    let id: Int64
    let sender: String
    let subject: String
    let snippet: String
    let formattedDate: String
    let isRead: Bool
    let isImportant: Bool
    let hasAttachments: Bool
    let tagName: String?
    let tagColorHex: String?
    let avatarInitials: String
    let avatarBgColor: Color

    init(mail: MailItem) {
        self.id = mail.id
        self.sender = mail.displayName()
        self.subject = mail.displaySubject()
        self.snippet = mail.snippet
        self.formattedDate = DateUtils.formatDate(mail.createdAt)
        self.isRead = mail.read
        self.isImportant = mail.important
        self.hasAttachments = mail.hasAttachments
        self.tagName = mail.tagName
        self.tagColorHex = mail.tagColor

        let emailKey = !mail.fromEmail.isEmpty ? mail.fromEmail : mail.sender
        self.avatarInitials = AvatarGenerator.initials(displayName: mail.displayName(), email: emailKey)
        self.avatarBgColor = AvatarGenerator.backgroundColor(for: emailKey)
    }
}