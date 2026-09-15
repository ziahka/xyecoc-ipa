//
//  MailStatsView.swift
//  XyecocMail
//
//  Local mailbox statistics built entirely from the offline cache of the
//  active account: totals, a 7-day activity chart and the most active
//  senders. No network requests are made; counts reflect whatever is
//  currently cached on the device.
//

import SwiftUI

// MARK: - ViewModel

@MainActor
final class MailStatsViewModel: ObservableObject {

    struct DayCount: Identifiable {
        let id: Int            // day offset, 0 = today, 6 = 6 days ago
        let label: String
        let count: Int
        let isToday: Bool
    }

    struct SenderCount: Identifiable {
        let id: String         // sender identity (email or raw sender)
        let name: String
        let email: String
        let count: Int
    }

    @Published var total = 0
    @Published var unread = 0
    @Published var important = 0
    @Published var withAttachments = 0
    @Published var receivedLast7Days = 0
    @Published var days: [DayCount] = []
    @Published var topSenders: [SenderCount] = []
    @Published var isEmpty = true
    @Published var isLoading = true

    private let dayLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "d MMM"
        return f
    }()

    func load() async {
        let mails = await MailDatabase.shared.allMails()
        total = mails.count
        unread = mails.filter { !$0.read }.count
        important = mails.filter { $0.important }.count
        withAttachments = mails.filter { $0.hasAttachments }.count

        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)

        // Bucket cached letters into the last 7 calendar days.
        var buckets: [Int: Int] = [:]
        for mail in mails {
            guard let date = DateUtils.parseISO(mail.createdAt) else { continue }
            let offset = calendar.dateComponents(
                [.day], from: calendar.startOfDay(for: date), to: todayStart).day
            guard let offset, offset >= 0, offset < 7 else { continue }
            buckets[offset, default: 0] += 1
        }
        receivedLast7Days = buckets.values.reduce(0, +)

        days = (0...6).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: now) ?? now
            let label: String
            switch offset {
            case 0:  label = NSLocalizedString("Сегодня", comment: "Stats chart day label")
            case 1:  label = NSLocalizedString("Вчера", comment: "Stats chart day label")
            default: label = dayLabelFormatter.string(from: date)
            }
            return DayCount(id: offset,
                            label: label,
                            count: buckets[offset] ?? 0,
                            isToday: offset == 0)
        }

        struct Acc { var name: String; var email: String; var count: Int }
        var bySender: [String: Acc] = [:]
        for mail in mails {
            let key = mail.fromEmail.isEmpty ? mail.sender : mail.fromEmail
            guard !key.isEmpty else { continue }
            var acc = bySender[key] ?? Acc(name: mail.displayName(),
                                           email: mail.fromEmail,
                                           count: 0)
            acc.count += 1
            bySender[key] = acc
        }
        topSenders = bySender
            .map { SenderCount(id: $0.key,
                               name: $0.value.name,
                               email: $0.value.email,
                               count: $0.value.count) }
            .sorted { ($0.count, $0.name) > ($1.count, $1.name) }
            .prefix(5)
            .map { $0 }

        isEmpty = mails.isEmpty
        isLoading = false
    }
}

// MARK: - Screen

struct MailStatsView: View {
    @StateObject private var vm = MailStatsViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.isEmpty {
                    emptyState
                } else {
                    List {
                        overviewSection
                        weeklyChartSection
                        sendersSection
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Статистика")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Готово") { dismiss() }
                }
            }
            .task { await vm.load() }
        }
    }

    // MARK: Sections

    private var overviewSection: some View {
        Section {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                statCard(icon: "envelope.fill", label: "Всего в кэше", value: vm.total)
                statCard(icon: "envelope.badge.fill", label: "Непрочитанных", value: vm.unread)
                statCard(icon: "star.fill", label: "Важных", value: vm.important)
                statCard(icon: "paperclip", label: "С вложениями", value: vm.withAttachments)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Обзор")
        } footer: {
            Text("Данные собраны из локального кэша текущего аккаунта.")
        }
    }

    private var weeklyChartSection: some View {
        Section {
            let maxCount = max(vm.days.map(\.count).max() ?? 1, 1)
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(vm.days) { day in
                        VStack(spacing: 5) {
                            Text("\(day.count)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(day.count > 0 ? Color.primary : Color.secondary.opacity(0.5))
                            RoundedRectangle(cornerRadius: 4)
                                .fill(day.isToday ? Color.accentColor : Color.accentColor.opacity(0.4))
                                .frame(height: max(4, CGFloat(day.count) / CGFloat(maxCount) * 110))
                                .frame(maxWidth: .infinity)
                            Text(day.label)
                                .font(.caption2)
                                .foregroundStyle(day.isToday ? Color.accentColor : Color.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                }
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Поступило за 7 дней: \(vm.receivedLast7Days)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
        } header: {
            Text("Активность за 7 дней")
        }
    }

    @ViewBuilder
    private var sendersSection: some View {
        if !vm.topSenders.isEmpty {
            Section("Топ отправителей") {
                let maxCount = max(vm.topSenders.map(\.count).max() ?? 1, 1)
                ForEach(vm.topSenders) { sender in
                    HStack(spacing: 12) {
                        AvatarView(email: sender.email, displayName: sender.name, size: 36)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(sender.name)
                                .font(.subheadline)
                                .lineLimit(1)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.secondary.opacity(0.15))
                                    Capsule()
                                        .fill(Color.accentColor.opacity(0.7))
                                        .frame(width: max(6, geo.size.width * CGFloat(sender.count) / CGFloat(maxCount)))
                                }
                            }
                            .frame(height: 5)
                        }
                        Text("\(sender.count)")
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: Helpers

    private func statCard(icon: String, label: String, value: Int) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
            Text("\(value)")
                .font(.title2.monospacedDigit().bold())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.accentColor.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .foregroundStyle(.secondary)
            Text("Статистика появится после синхронизации писем")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
