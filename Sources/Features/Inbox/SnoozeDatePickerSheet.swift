import SwiftUI

/// Лист «Своё время…» — произвольные дата и время для отложки письма.
struct SnoozeDatePickerSheet: View {
    @State private var date = Date().addingTimeInterval(3_600)
    let onConfirm: (Date) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DatePicker(
                    "Вернуть письмо",
                    selection: $date,
                    in: Date()...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.graphical)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                Spacer()
            }
            .navigationTitle("Отложить на…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Отложить") {
                        // Не даём выбрать прошедший момент: минимум минута вперёд.
                        onConfirm(max(date, Date().addingTimeInterval(60)))
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                }
            }
        }
        .presentationDetents([.medium])
    }
}
