import SwiftUI

/// Local sender blacklist backed by UserDefaults. Blocked addresses are
/// filtered out of every mail list immediately; server-side blocking
/// (mail-action "block") stays a separate, complementary mechanism.
enum BlockedSendersStore {
    private static let key = "blocked_senders"

    static var blocked: [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func isBlocked(_ email: String) -> Bool {
        let lower = email.lowercased()
        return blocked.contains { $0.lowercased() == lower }
    }

    static func block(_ email: String) {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var list = blocked
        guard !list.contains(where: { $0.lowercased() == trimmed.lowercased() }) else { return }
        list.append(trimmed)
        UserDefaults.standard.set(list, forKey: key)
    }

    static func unblock(_ email: String) {
        let list = blocked.filter { $0.lowercased() != email.lowercased() }
        UserDefaults.standard.set(list, forKey: key)
    }
}

/// Management screen for the local sender blacklist.
struct BlockedSendersView: View {
    @State private var senders = BlockedSendersStore.blocked

    var body: some View {
        Group {
            if senders.isEmpty {
                ScrollView {
                    EmptyStateView(
                        icon: "person.crop.circle.badge.xmark",
                        title: "Список пуст",
                        subtitle: "Заблокируйте отправителя из контекстного меню письма — его письма перестанут показываться в списках.")
                }
            } else {
                List {
                    ForEach(senders, id: \.self) { sender in
                        HStack(spacing: 12) {
                            AvatarView(email: sender, size: 32)
                            Text(sender)
                                .font(.subheadline)
                                .lineLimit(1)
                            Spacer()
                        }
                    }
                    .onDelete(perform: remove)
                }
            }
        }
        .navigationTitle("Чёрный список")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !senders.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
            }
        }
    }

    private func remove(at offsets: IndexSet) {
        for index in offsets { BlockedSendersStore.unblock(senders[index]) }
        senders = BlockedSendersStore.blocked
        Haptics.warning()
    }
}
