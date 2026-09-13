import SwiftUI
@preconcurrency import WebKit
import UIKit

struct MailReaderView: View {
    let mailId: Int64
    var siblingIds: [Int64] = []
    var onChange: () -> Void = {}

    @StateObject private var vm = ReaderViewModel()
    @FocusState private var isReplyFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showFolderPicker = false
    @State private var composeSeed: ComposeSeed?
    @State private var shareItems: [Any]? = nil
    @State private var webViewHeight: CGFloat = 300
    @State private var currentMailId: Int64
    @State private var dragOffset: CGFloat = 0

    init(mailId: Int64, siblingIds: [Int64] = [], onChange: @escaping () -> Void = {}) {
        self.mailId = mailId
        self.siblingIds = siblingIds
        self.onChange = onChange
        _currentMailId = State(initialValue: mailId)
    }

    private var hasPrev: Bool {
        guard let idx = siblingIds.firstIndex(of: currentMailId) else { return false }
        return idx > 0
    }
    private var hasNext: Bool {
        guard let idx = siblingIds.firstIndex(of: currentMailId) else { return false }
        return idx < siblingIds.count - 1
    }

    var body: some View {
        Group {
            if vm.isLoading && vm.details == nil {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let mail = vm.details {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            headerCard(mail)
                            ReaderWebView(html: styledHTML, isDark: colorScheme == .dark, dynamicHeight: $webViewHeight)
                                .frame(height: max(webViewHeight, 150))
                            attachmentsBar(mail)
                        }
                    }
                    .scrollDismissesKeyboard(.interactively)

                    Divider()

                    actionBar

                    Divider()

                    quickReplyBar
                }
                .offset(x: dragOffset)
                .gesture(swipeGesture)
            } else {
                Text("Не удалось загрузить письмо").foregroundStyle(.secondary)
            }
        }
        .navigationTitle(vm.details?.getDisplaySubjectSafe() ?? "Письмо")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) { moreMenu }
        }
        .sheet(isPresented: $showFolderPicker) { folderPicker }
        .sheet(item: $composeSeed) { seed in ComposeView(seed: seed) }
        .sheet(isPresented: Binding(
            get: { shareItems != nil },
            set: { if !$0 { shareItems = nil } }
        )) {
            if let items = shareItems {
                ShareSheet(activityItems: items)
            }
        }
        .alert("Ошибка", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
        .task { await vm.load(mailId: currentMailId) }
        .onChange(of: currentMailId) { newId in
            webViewHeight = 300
            Task { await vm.load(mailId: newId) }
        }
        .onDisappear { onChange() }
    }

    // MARK: - Action Bar (Apple Mail pattern)

    private var actionBar: some View {
        HStack(spacing: 0) {
            actionButton(icon: "arrowshape.turn.up.left.fill", label: "Ответить") {
                composeSeed = replySeed()
            }
            actionButton(icon: "arrowshape.turn.up.right.fill", label: "Переслать") {
                composeSeed = forwardSeed()
            }
            actionButton(icon: "star", label: "Важное") {
                Task { await vm.markImportant() }
            }
            actionButton(icon: "folder.fill", label: "Папка") {
                showFolderPicker = true
            }
            actionButton(icon: "trash.fill", label: "Удалить") {
                Task { await vm.deleteCurrent(); dismiss() }
            }
        }
        .padding(.vertical, 4)
    }

    private func actionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.light()
            action()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.body)
                Text(label).font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Swipe navigation

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 50)
            .onChanged { value in
                dragOffset = value.translation.width * 0.3
            }
            .onEnded { value in
                let threshold: CGFloat = 80
                withAnimation(.easeOut(duration: 0.2)) { dragOffset = 0 }
                if value.translation.width < -threshold, hasNext {
                    navigateNext()
                } else if value.translation.width > threshold, hasPrev {
                    navigatePrev()
                }
            }
    }

    private func navigateNext() {
        guard let idx = siblingIds.firstIndex(of: currentMailId), idx < siblingIds.count - 1 else { return }
        Haptics.light()
        currentMailId = siblingIds[idx + 1]
    }

    private func navigatePrev() {
        guard let idx = siblingIds.firstIndex(of: currentMailId), idx > 0 else { return }
        Haptics.light()
        currentMailId = siblingIds[idx - 1]
    }

    private var quickReplyBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Быстрый ответ…", text: $vm.quickReplyText, axis: .vertical)
                .lineLimit(1...4)
                .focused($isReplyFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18))

            Button {
                Task {
                    isReplyFocused = false
                    let success = await vm.sendQuickReply()
                    if success {
                        onChange()
                    }
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(vm.quickReplyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              ? Color.secondary.opacity(0.3)
                              : Color.accentColor)
                        .frame(width: 36, height: 36)

                    if vm.isQuickReplying {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .offset(x: -1, y: 1)
                    }
                }
            }
            .disabled(vm.quickReplyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.isQuickReplying)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    private var moreMenu: some View {
        Menu {
            Button { composeSeed = replySeed() } label: {
                Label("Ответить", systemImage: "arrowshape.turn.up.left")
            }
            Button { composeSeed = forwardSeed() } label: {
                Label("Переслать", systemImage: "arrowshape.turn.up.right")
            }
            Divider()
            Button { Task { await vm.markImportant() } } label: {
                Label("Пометить как важное", systemImage: "star")
            }
            Button { showFolderPicker = true } label: {
                Label("Переместить в папку", systemImage: "folder")
            }
            Button { Task { await vm.blockSender() } } label: {
                Label("Заблокировать отправителя", systemImage: "hand.raised")
            }
            Divider()
            Button { exportAsImage() } label: {
                Label("Поделиться как изображение (PNG)", systemImage: "photo")
            }
            Button { exportAsPDF() } label: {
                Label("Экспортировать в PDF", systemImage: "doc.richtext")
            }
            Divider()
            Button(role: .destructive) { Task { await vm.report("spam") } } label: {
                Label("Пожаловаться на спам", systemImage: "exclamationmark.octagon")
            }
        } label: {
            Image(systemName: "ellipsis")
        }
    }

    private func quotedBody(_ d: MailDetails) -> String {
        let header = "<b>От:</b> \(d.getDisplayNameSafe()) &lt;\(d.fromEmail ?? "")&gt;<br>"
            + "<b>Кому:</b> \(d.to ?? "")<br>"
            + "<b>Дата:</b> \(DateUtils.formatDate(d.createdAt))<br>"
            + "<b>Тема:</b> \(d.subject ?? "")<br><br>"
        return "<br><br><blockquote style=\"margin-left:10px;padding-left:10px;border-left:3px solid #ccc;color:#555;\">"
            + header + vm.html + "</blockquote>"
    }

    private func replySeed() -> ComposeSeed {
        guard let d = vm.details else { return ComposeSeed() }
        let subject = d.getDisplaySubjectSafe()
        let re = subject.lowercased().hasPrefix("re:") ? subject : "Re: \(subject)"
        return ComposeSeed(to: d.fromEmail ?? "", subject: re, body: quotedBody(d))
    }

    private func forwardSeed() -> ComposeSeed {
        guard let d = vm.details else { return ComposeSeed() }
        let subject = d.subject ?? d.getDisplaySubjectSafe()
        let fwd = subject.lowercased().hasPrefix("fwd:") ? subject : "Fwd: \(subject)"
        return ComposeSeed(to: "", subject: fwd, body: quotedBody(d))
    }

    private func headerCard(_ mail: MailDetails) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(mail.getDisplaySubjectSafe())
                .font(.title3).fontWeight(.bold)
            HStack(spacing: 12) {
                AvatarView(
                    email: mail.fromEmail ?? mail.sender ?? "",
                    displayName: mail.getDisplayNameSafe(),
                    size: 44
                )
                VStack(alignment: .leading, spacing: 1) {
                    Text(mail.getDisplayNameSafe()).fontWeight(.semibold)
                    Text(mail.fromEmail ?? "").font(.caption).foregroundStyle(.secondary)
                    Text("Кому: \(mail.to ?? "")").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(DateUtils.formatDate(mail.createdAt))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding([.horizontal, .top])
    }

    @ViewBuilder
    private func attachmentsBar(_ mail: MailDetails) -> some View {
        let attachments = mail.validAttachments()
        if !attachments.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Divider()
                Text("Вложения (\(attachments.count)):")
                    .font(.subheadline).fontWeight(.bold)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(attachments) { attach in
                            Button {
                                if let url = attachmentURL(attach) { openURL(url) }
                            } label: {
                                Label("\(attach.fileName) (\(DateUtils.formatFileSize(attach.fileSize)))",
                                      systemImage: "paperclip")
                                    .font(.caption)
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(Color.secondary.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding()
        }
    }

    private var folderPicker: some View {
        NavigationStack {
            List(vm.folders) { folder in
                Button {
                    Task { await vm.move(toFolder: folder) }
                    showFolderPicker = false
                } label: {
                    Label(folder.name, systemImage: "folder")
                }
            }
            .navigationTitle("Выберите папку")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { showFolderPicker = false }
                }
            }
        }
    }

    private func attachmentURL(_ attach: Attachment) -> URL? {
        let token = KeychainManager.shared.getToken() ?? ""
        let datePart = String(attach.createdAt.split(separator: "T").first ?? "")
        let path = "https://cdn.xyecoc.com/data/attachments/mails/\(datePart)/\(attach.id).\(attach.fileExtension)?token=\(token)"
        return URL(string: path)
    }

    private func exportAsImage() {
        guard let details = vm.details else { return }
        if let image = EmailExportService.shared.renderToImage(details: details, bodyText: vm.html) {
            shareItems = [image]
        }
    }

    private func exportAsPDF() {
        guard let details = vm.details else { return }
        if let pdfURL = EmailExportService.shared.renderToPDF(details: details, bodyText: vm.html) {
            shareItems = [pdfURL]
        }
    }

    private var styledHTML: String {
        let dark = colorScheme == .dark
        let textColor = dark ? "#E0E0E0" : "#212121"
        let bgColor = dark ? "#121212" : "#FFFFFF"
        let linkColor = dark ? "#8AB4F8" : "#1A73E8"
        return """
        <!DOCTYPE html><html><head>\
        <meta name="viewport" content="width=device-width, initial-scale=1.0">\
        <style>\
        html, body { margin: 0; padding: 16px; background-color: \(bgColor); color: \(textColor); \
        font-family: -apple-system, BlinkMacSystemFont, sans-serif; font-size: 16px; line-height: 1.6; \
        word-break: break-word; }\
        img { max-width: 100% !important; height: auto !important; border-radius: 8px; }\
        table { max-width: 100% !important; }\
        a { color: \(linkColor); text-decoration: underline; }\
        blockquote { margin: 12px 0; padding-left: 12px; border-left: 3px solid #888; color: #888; }\
        </style></head><body>\(vm.html)</body></html>
        """
    }
}

struct ReaderWebView: UIViewRepresentable {
    let html: String
    let isDark: Bool
    @Binding var dynamicHeight: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        guard context.coordinator.loadedHTML != html else { return }
        context.coordinator.loadedHTML = html

        let baseURL = URL(string: "https://cdn.xyecoc.com")
        if let token = KeychainManager.shared.getToken(), !token.isEmpty,
           let cookie = HTTPCookie(properties: [
                .domain: ".xyecoc.com", .path: "/",
                .name: "authorization", .value: token
           ]) {
            webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) {
                DispatchQueue.main.async {
                    webView.loadHTMLString(self.html, baseURL: baseURL)
                }
            }
        } else {
            webView.loadHTMLString(html, baseURL: baseURL)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: ReaderWebView
        var loadedHTML: String?

        init(parent: ReaderWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            webView.evaluateJavaScript("Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)") { result, _ in
                if let height = result as? CGFloat, height > 0 {
                    DispatchQueue.main.async {
                        self.parent.dynamicHeight = height
                    }
                }
            }
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}

extension MailDetails {
    func getDisplayNameSafe() -> String {
        if let n = fromName, !n.isEmpty { return n }
        if let s = sender, !s.isEmpty { return s }
        if let e = fromEmail, !e.isEmpty { return e }
        return "Неизвестный"
    }
    func getDisplaySubjectSafe() -> String {
        if let s = subject, !s.isEmpty { return s }
        if let sn = snippet, !sn.isEmpty { return sn }
        return "Без темы"
    }
}
