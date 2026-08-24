//
//  MailRow.swift
//  XyecocMail
//

import SwiftUI

struct MailRow: View {
    let mail: MailItem

    private var avatarLetter: String {
        guard let c = mail.displayName().first else { return "?" }
        return String(c).uppercased()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(mail.read ? Color.secondary.opacity(0.3) : Color.accentColor)
                    .frame(width: 44, height: 44)
                Text(avatarLetter)
                    .font(.headline)
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(mail.displayName())
                        .font(.subheadline)
                        .fontWeight(mail.read ? .regular : .bold)
                        .lineLimit(1)

                    Spacer()

                    Text(DateUtils.formatDate(mail.createdAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !mail.read {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 8, height: 8)
                    }
                }

                Text(mail.displaySubject())
                    .font(.subheadline)
                    .fontWeight(mail.read ? .regular : .semibold)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if !mail.snippet.isEmpty {
                        Text(mail.snippet)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if mail.hasAttachments {
                        Image(systemName: "paperclip")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if mail.important {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                }

                if let tag = mail.tagName, !tag.isEmpty {
                    TagBadge(name: tag, colorHex: mail.tagColor)
                }
            }
        }
        .padding(.vertical, 2)
    }
}