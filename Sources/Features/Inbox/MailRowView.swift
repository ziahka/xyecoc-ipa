import SwiftUI

struct MailRowView: View {
    let state: MailRowState

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(state.isRead ? state.avatarBgColor.opacity(0.35) : state.avatarBgColor)
                    .frame(width: 44, height: 44)

                Text(state.avatarInitials)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(state.sender)
                        .font(.subheadline)
                        .fontWeight(state.isRead ? .regular : .bold)
                        .lineLimit(1)

                    Spacer()

                    Text(state.formattedDate)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !state.isRead {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 8, height: 8)
                    }
                }

                Text(state.subject)
                    .font(.subheadline)
                    .fontWeight(state.isRead ? .regular : .semibold)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if !state.snippet.isEmpty {
                        Text(state.snippet)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if state.hasAttachments {
                        Image(systemName: "paperclip")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if state.isImportant {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                }

                if let tag = state.tagName, !tag.isEmpty {
                    TagBadge(name: tag, colorHex: state.tagColorHex)
                }
            }
        }
        .padding(.vertical, 2)
    }
}