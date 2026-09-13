import SwiftUI

struct EmailShareCardView: View {
    let details: MailDetails
    let bodyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                AvatarView(
                    email: details.fromEmail ?? details.sender ?? "",
                    displayName: details.getDisplayNameSafe(),
                    size: 52
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(details.getDisplayNameSafe())
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.black)

                    if let email = details.fromEmail, !email.isEmpty {
                        Text(email)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(.gray)
                    }

                    if let to = details.to, !to.isEmpty {
                        Text("To: \(to)")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.gray)
                    }
                }

                Spacer()

                if let dateStr = details.createdAt {
                    Text(DateUtils.formatDate(dateStr))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.gray)
                }
            }

            Divider()

            Text(details.getDisplaySubjectSafe())
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.black)

            Text(cleanedBodyText)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.black)
                .lineSpacing(4)

            let attachments = details.validAttachments()
            if !attachments.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Attachments (\(attachments.count)):")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.gray)
                    ForEach(attachments) { attach in
                        HStack(spacing: 6) {
                            Image(systemName: "paperclip")
                                .font(.system(size: 12))
                                .foregroundStyle(.gray)
                            Text(attach.fileName)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.black)
                            Spacer()
                            Text(DateUtils.formatFileSize(attach.fileSize))
                                .font(.system(size: 11))
                                .foregroundStyle(.gray)
                        }
                    }
                }
            }

            Spacer(minLength: 16)

            HStack {
                Spacer()
                Text("Rendered via Xyecoc Mail for iOS")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.gray.opacity(0.8))
            }
        }
        .padding(24)
        .frame(width: 580)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.gray.opacity(0.25), lineWidth: 1)
        )
    }

    private var cleanedBodyText: String {
        let raw = bodyText.isEmpty ? (details.snippet ?? "") : bodyText
        var text = raw
        text = text.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "</p>", with: "\n\n")
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&apos;", with: "'")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
