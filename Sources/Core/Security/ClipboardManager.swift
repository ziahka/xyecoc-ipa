import UIKit

@MainActor
final class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()

    private var activeDestructTask: Task<Void, Never>?

    private init() {}

    func copySecurely(text: String, timeout: TimeInterval = 60) {
        activeDestructTask?.cancel()
        activeDestructTask = nil

        UIPasteboard.general.string = text

        activeDestructTask = Task { [weak self] in
            do {
                let nanoseconds = UInt64(timeout * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            self?.flushIfMatching(text)
        }
    }

    func flushImmediately() {
        activeDestructTask?.cancel()
        activeDestructTask = nil
        UIPasteboard.general.string = ""
    }

    private func flushIfMatching(_ expectedText: String) {
        if let currentText = UIPasteboard.general.string, currentText == expectedText {
            UIPasteboard.general.string = ""
        }
    }
}
