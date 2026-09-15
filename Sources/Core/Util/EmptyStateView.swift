import SwiftUI

/// Reusable empty-state placeholder: tinted icon medallion, title,
/// optional subtitle and optional capsule action button. Used across
/// mail lists and management screens so empty screens look consistent.
struct EmptyStateView: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var actionTitle: String? = nil
    var actionSystemImage: String = "arrow.clockwise"
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 92, height: 92)
                Image(systemName: icon)
                    .resizable().scaledToFit()
                    .frame(width: 40, height: 40)
                    .foregroundStyle(Color.accentColor)
            }
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let action, let actionTitle {
                Button {
                    Haptics.light()
                    action()
                } label: {
                    Label(actionTitle, systemImage: actionSystemImage)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity)
    }
}
