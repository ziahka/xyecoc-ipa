import SwiftUI
@preconcurrency import WebKit
import UIKit

struct MailReaderView: View {
    let mailId: Int64
    var onChange: () -> Void = {}

    @StateObject private var vm = ReaderViewModel()
    @FocusState private var isReplyFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showFolderPicker = false
    @State private var composeSeed: ComposeSeed?

    var body: some View {
        Group {
            if vm.isLoading && vm.details == nil {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let mail = vm.details {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            headerCard(mail)
                            ReaderWebView(html: styledHTML, isDark: colorScheme == .dark)
                                .frame(minHeight: 300)
                            attachmentsBar(mail)
                        }
                    }
                    .scrollDismissesKeyboard(.interactively)

                    Divider()

                    quickReplyBar
                }
            } else {
                Text("Не удалось загрузить письмо").foregroundStyle(.secondary)
            }
        }
        .navigationTitle(vm.details?.getDisplaySubjectSafe() ?? "Письмо")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { composeSeed = replySeed() } label: {
                    Image(systemName: "arrowshape.turn.up.left")
                }
                .disabled(vm.details == nil)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await vm.deleteCurrent(); dismiss() }
                } label: { Image(systemName: "trash") }
            }
            ToolbarItem(placement: .navigationBarTrailing) { moreMenu }
        }
        .sheet(isPresented: $showFolderPicker) { folderPicker }
        .sheet(item: $composeSeed) { seed in ComposeView(seed: seed) }
        .alert("Ошибка", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
        .task { await vm.load(mailId: mailId) }
        .onDisappear { onChange() }
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
                ZStack {
                    Circle().fill(Color.brand.opacity(0.25)).frame(width: 44, height: 44)
                    Text(initial(mail.getDisplayNameSafe()))
                        .font(.headline).foregroundStyle(Color.brand)
                }
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
                    Task { await vm.move(toFolderId: folder.id) }
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

    private func initial(_ s: String) -> String {
        s.first.map { String($0).uppercased() } ?? "?"
    }

    private func attachmentURL(_ attach: Attachment) -> URL? {
        let token = KeychainManager.shared.getToken() ?? ""
        let datePart = String(attach.createdAt.split(separator: "T").first ?? "")
        let path = "https://cdn.xyecoc.com/data/attachments/mails/\(datePart)/\(attach.id).\(attach.fileExtension)?token=\(token)"
        return URL(string: path)
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
        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; color: \(textColor); \
        background-color: \(bgColor); margin: 16px; padding: 0; line-height: 1.6; \
        font-size: 16px; word-break: break-word; }\
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

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false

        if let token = KeychainManager.shared.getToken(), !token.isEmpty,
           let cookie = HTTPCookie(properties: [
                .domain: ".xyecoc.com", .path: "/",
                .name: "authorization", .value: token
           ]) {
            config.websiteDataStore.httpCookieStore.setCookie(cookie)
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedHTML != html else { return }
        context.coordinator.loadedHTML = html
        webView.loadHTMLString(html, baseURL: URL(string: "https://cdn.xyecoc.com"))
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedHTML: String?

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
