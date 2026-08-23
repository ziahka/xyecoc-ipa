//
//  MailReaderView.swift
//  XyecocMail
//
//  Port of `ReaderScreen.kt` + `ReaderViewModel`. Loads details via `mail/view`,
//  fetches the rendered HTML body from the CDN (cookie-authenticated in the
//  repository), and renders it in a JS-disabled WKWebView. Marks the mail read
//  in the local cache on open; the inbox refreshes via the `onChange` callback.
//

import SwiftUI
import WebKit
import UIKit

// MARK: - ViewModel

@MainActor
final class ReaderViewModel: ObservableObject {

    @Published var details: MailDetails?
    @Published var html: String = ""
    @Published var isLoading = false
    @Published var folders: [Folder] = []
    @Published var tags: [Tag] = []

    private let repo = MailRepository()
    private let db = MailDatabase.shared

    func load(mailId: Int64) async {
        isLoading = true
        folders = await db.folders()
        tags = await db.tags()

        let response = await repo.fetchMailDetails(mailId: mailId)
        if let d = response.mailDetails() {
            details = d
            let body = await repo.fetchMailBodyHtml(mailId: mailId)
            if !body.isEmpty {
                html = body
            } else if let message = d.message, !message.isEmpty {
                html = message
            } else {
                html = "<p style=\"font-family:sans-serif;font-size:16px;color:#333;line-height:1.5;\">\(d.snippet ?? "")</p>"
            }
            await db.setRead(mailId, true)
        }
        isLoading = false
    }

    func deleteCurrent() async {
        guard let id = details?.id else { return }
        let folder = await db.mail(id: id)?.folder
        _ = await repo.performMailAction(mailId: id, action: "delete", folder: folder)
    }

    func markImportant() async {
        guard let id = details?.id else { return }
        _ = await repo.performMailAction(mailId: id, action: "important")
    }

    func move(toFolderId folderId: Int64) async {
        guard let id = details?.id else { return }
        _ = await repo.performMailAction(mailId: id, action: "move-to-folder", value: .int(folderId))
    }

    func blockSender() async {
        guard let id = details?.id else { return }
        _ = await repo.blockSender(mailId: id)
    }

    func report(_ type: String) async {
        guard let id = details?.id else { return }
        _ = await repo.reportViolation(mailId: id, type: type)
    }
}

// MARK: - Screen

struct MailReaderView: View {

    let mailId: Int64
    var onChange: () -> Void = {}

    @StateObject private var vm = ReaderViewModel()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showFolderPicker = false

    var body: some View {
        Group {
            if vm.isLoading && vm.details == nil {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let mail = vm.details {
                VStack(spacing: 0) {
                    headerCard(mail)
                    ReaderWebView(html: styledHTML, isDark: colorScheme == .dark)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    attachmentsBar(mail)
                }
            } else {
                Text("Не удалось загрузить письмо").foregroundStyle(.secondary)
            }
        }
        .navigationTitle(vm.details?.getDisplaySubjectSafe() ?? "Письмо")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await vm.deleteCurrent(); dismiss() }
                } label: { Image(systemName: "trash") }
            }
            ToolbarItem(placement: .navigationBarTrailing) { moreMenu }
        }
        .sheet(isPresented: $showFolderPicker) { folderPicker }
        .task { await vm.load(mailId: mailId) }
        .onDisappear { onChange() }
    }

    private var moreMenu: some View {
        Menu {
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

    private func headerCard(_ mail: MailDetails) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(mail.getDisplaySubjectSafe())
                .font(.title3).fontWeight(.bold)
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.accentColor.opacity(0.25)).frame(width: 44, height: 44)
                    Text(initial(mail.getDisplayNameSafe()))
                        .font(.headline).foregroundStyle(Color.accentColor)
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

    // Build the CDN attachment download URL (matches ReaderScreen.kt).
    private func attachmentURL(_ attach: Attachment) -> URL? {
        let token = KeychainManager.shared.getToken() ?? ""
        let datePart = String(attach.createdAt.split(separator: "T").first ?? "")
        let path = "https://cdn.xyecoc.com/data/attachments/mails/\(datePart)/\(attach.id).\(attach.fileExtension)?token=\(token)"
        return URL(string: path)
    }

    // Themed HTML wrapper (ported from ReaderScreen.kt).
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

// MARK: - WKWebView wrapper

struct ReaderWebView: UIViewRepresentable {
    let html: String
    let isDark: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false // untrusted mail HTML

        // Best-effort: authenticate inline CDN images with the token cookie.
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
        // Only reload when the content actually changes (avoids flicker loops).
        guard context.coordinator.loadedHTML != html else { return }
        context.coordinator.loadedHTML = html
        webView.loadHTMLString(html, baseURL: URL(string: "https://cdn.xyecoc.com"))
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedHTML: String?

        // Open tapped links in the system browser instead of inside the reader.
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

// MARK: - MailDetails display helpers (kept out of Models.swift to avoid churn)

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
