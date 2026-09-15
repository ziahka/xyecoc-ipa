import SwiftUI

/// Строка письма в списке. Плотность и превью настраиваются
/// («list_density», «row_preview»); значения читаются напрямую —
/// настройка применяется при следующей перерисовке списка.
struct MailRowView: View {
    let state: MailRowState

    private var density: ListDensity { Prefs.listDensity }
    private var preview: RowPreview { Prefs.rowPreview }

    private var avatarSize: CGFloat {
        switch density {
        case .compact: return 36
        case .regular: return 44
        case .spacious: return 46
        }
    }

    private var verticalPadding: CGFloat {
        switch density {
        case .compact: return 0
        case .regular: return 2
        case .spacious: return 6
        }
    }

    private var lineSpacing: CGFloat {
        switch density {
        case .compact: return 2
        case .regular: return 3
        case .spacious: return 5
        }
    }

    private var titleFont: Font {
        density == .compact ? .footnote : .subheadline
    }

    private var subjectFont: Font {
        density == .compact ? .footnote : .subheadline
    }

    private var snippetFont: Font {
        density == .spacious ? .footnote : .caption
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AvatarView(email: state.email, displayName: state.sender, size: avatarSize)
                .opacity(state.isRead ? 0.6 : 1.0)

            VStack(alignment: .leading, spacing: lineSpacing) {
                HStack {
                    Text(state.sender)
                        .font(titleFont)
                        .fontWeight(state.isRead ? .regular : .bold)
                        .lineLimit(1)

                    Spacer()

                    Text(state.formattedDate)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if state.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }

                    if !state.isRead {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 8, height: 8)
                    }
                }

                Text(state.subject)
                    .font(subjectFont)
                    .fontWeight(state.isRead ? .regular : .semibold)
                    .lineLimit(1)

                if preview != .hidden {
                    HStack(spacing: 6) {
                        if !state.snippet.isEmpty {
                            Text(state.snippet)
                                .font(snippetFont)
                                .foregroundStyle(.secondary)
                                .lineLimit(preview == .oneLine ? 1 : 2)
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
                }

                if let tag = state.tagName, !tag.isEmpty {
                    TagBadge(name: tag, colorHex: state.tagColorHex)
                }
            }
        }
        .padding(.vertical, verticalPadding)
    }
}
