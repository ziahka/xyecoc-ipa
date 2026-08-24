//
//  ComposeView.swift
//  XyecocMail
//
//  Port of `ComposeScreen.kt` + `ComposeViewModel`. Compose / reply / forward
//  with a rich (HTML) body, signature auto-append, and native attachment
//  import via PhotosPicker and .fileImporter (base64-encoded to match
//  `MailRepository.sendMail`).
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Seed for reply / forward presentation

struct ComposeSeed: Identifiable {
    let id = UUID()
    var to: String = ""
    var subject: String = ""
    var body: String = ""
}

// MARK: - ViewModel

@MainActor
final class ComposeViewModel: ObservableObject {

    @Published var isSending = false
    @Published var signature = ""
    @Published var aliases: [AliasAddress] = []

    private let mailRepo = MailRepository()
    private let settingsRepo = SettingsRepository()

    func load() async {
        let profile = await settingsRepo.getProfile()
        if let sig = profile.signature, !sig.isEmpty { signature = sig }
        let addresses = await settingsRepo.fetchAddresses()
        if let list = addresses.addresses { aliases = list }
    }

    /// Returns nil on success, or a localized error message on failure.
    func send(recipients: String,
              subject: String,
              body: String,
              attachments: [Attachment],
              isDraft: Bool) async -> String? {
        let users = recipients
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if users.isEmpty { return "Укажите получателя" }

        let fullBody: String
        if !isDraft && !signature.isEmpty && !body.contains(signature) {
            fullBody = "\(body)<br><br>\(signature)"
        } else {
            fullBody = body
        }

        isSending = true
        let response = await mailRepo.sendMail(recipients: users,
                                               subject: subject,
                                               messageHtml: fullBody,
                                               attachments: attachments,
                                               isDraft: isDraft)
        isSending = false
        return response.isSuccess() ? nil : (response.message ?? "Ошибка при отправке письма")
    }
}

// MARK: - Screen

struct ComposeView: View {

    @StateObject private var vm = ComposeViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private let replyMode: Bool

    @State private var to: String
    @State private var subject: String
    @State private var bodyText: String
    @State private var attachments: [Attachment] = []
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showFileImporter = false
    @State private var errorText: String?
    @State private var showSendDisabled = false

    private let senderEmail = KeychainManager.shared.getEmail() ?? ""
    @State private var selectedSender: String

    init(seed: ComposeSeed = ComposeSeed()) {
        _to = State(initialValue: seed.to)
        _subject = State(initialValue: seed.subject)
        _bodyText = State(initialValue: seed.body)
        _selectedSender = State(initialValue: KeychainManager.shared.getEmail() ?? "")
        replyMode = seed.subject.lowercased().hasPrefix("re:")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !vm.aliases.isEmpty { senderPicker }
                    field(title: "Кому", systemImage: "at", text: $to,
                          placeholder: "email@example.com (через запятую)")
                    field(title: "Тема", systemImage: "text.alignleft", text: $subject,
                          placeholder: "Тема письма")
                    formattingBar
                    bodyEditor
                    if !vm.signature.isEmpty { signaturePreview }
                    attachmentButtons
                    if !attachments.isEmpty { attachmentList }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(replyMode ? "Ответ на письмо" : "Новое письмо")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .task { await vm.load() }
            .fileImporter(isPresented: $showFileImporter,
                          allowedContentTypes: [.item],
                          allowsMultipleSelection: true,
                          onCompletion: handleFileImport)
            .onChange(of: photoItems) { _ in loadSelectedPhotos() }
            .alert("Не удалось", isPresented: Binding(
                get: { errorText != nil },
                set: { if !$0 { errorText = nil } })) {
                Button("OK", role: .cancel) { errorText = nil }
            } message: { Text(errorText ?? "") }
        }
        .alert("Отправка писем временно недоступна ✉️", isPresented: $showSendDisabled) {
            Button("Запросить доступ") {
                if let url = URL(string: "https://t.me/m/0asmI6p2OWU0") { openURL(url) }
                showSendDisabled = false
            }
            Button("Понятно", role: .cancel) { showSendDisabled = false }
        } message: {
            Text("Для защиты сервиса от спама отправка по умолчанию отключена для новых аккаунтов. Свяжитесь с поддержкой, чтобы включить её.")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Отмена") { dismiss() }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                Task { await saveDraft() }
            } label: { Image(systemName: "tray.and.arrow.down") }
            .disabled(vm.isSending || (to.isEmpty && subject.isEmpty && bodyText.isEmpty))
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            if vm.isSending {
                ProgressView()
            } else {
                Button {
                    Task { await sendMessage() }
                } label: { Image(systemName: "paperplane.fill") }
                .disabled(to.isEmpty)
            }
        }
    }

    // MARK: - Sections

    private var senderPicker: some View {
        Menu {
            Button("\(senderEmail) (Основной)") { selectedSender = senderEmail }
            ForEach(vm.aliases) { alias in
                Button(alias.email) { selectedSender = alias.email }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("От:").font(.caption).foregroundStyle(.secondary)
                    Text(selectedSender.isEmpty ? senderEmail : selectedSender)
                        .font(.subheadline).fontWeight(.semibold)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func field(title: String, systemImage: String,
                       text: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage).foregroundStyle(.secondary).frame(width: 20)
            TextField(placeholder, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var formattingBar: some View {
        HStack(spacing: 4) {
            formatButton("B", weight: .bold) { bodyText += "<b>текст</b>" }
            formatButton("I", italic: true) { bodyText += "<i>курсив</i>" }
            formatButton("U", underline: true) { bodyText += "<u>подчёркнутый</u>" }
            iconFormatButton("list.bullet") { bodyText += "<br>• Пункт 1<br>• Пункт 2" }
            iconFormatButton("text.quote") { bodyText += "<br><blockquote>Цитата</blockquote>" }
            Spacer()
        }
        .padding(6)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func formatButton(_ label: String, weight: Font.Weight = .regular,
                              italic: Bool = false, underline: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 16, weight: weight))
                .italic(italic)
                .underline(underline)
                .frame(width: 34, height: 30)
        }
        .buttonStyle(.plain)
    }

    private func iconFormatButton(_ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage).frame(width: 34, height: 30)
        }
        .buttonStyle(.plain)
    }

    private var bodyEditor: some View {
        ZStack(alignment: .topLeading) {
            if bodyText.isEmpty {
                Text("Напишите ваше сообщение…")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5).padding(.vertical, 10)
            }
            TextEditor(text: $bodyText)
                .frame(minHeight: 220)
                .scrollContentBackground(.hidden)
        }
        .padding(8)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var signaturePreview: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Подпись профиля (добавится автоматически):")
                .font(.caption2).foregroundStyle(.secondary)
            Text(vm.signature
                .replacingOccurrences(of: "<p>", with: "")
                .replacingOccurrences(of: "</p>", with: "")
                .replacingOccurrences(of: "<br>", with: " "))
                .font(.caption)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var attachmentButtons: some View {
        HStack(spacing: 10) {
            PhotosPicker(selection: $photoItems, matching: .images) {
                Label("Фото", systemImage: "photo")
                    .font(.subheadline)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(Capsule())
            }
            Button {
                showFileImporter = true
            } label: {
                Label("Файл", systemImage: "paperclip")
                    .font(.subheadline)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }

    private var attachmentList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Прикреплённые файлы (\(attachments.count)):")
                .font(.subheadline).fontWeight(.semibold)
            ForEach(attachments) { attach in
                HStack {
                    Image(systemName: "doc")
                    Text(attach.fileName).font(.subheadline).lineLimit(1)
                    Spacer()
                    Text(DateUtils.formatFileSize(attach.fileSize))
                        .font(.caption).foregroundStyle(.secondary)
                    Button {
                        attachments.removeAll { $0.id == attach.id }
                    } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // MARK: - Actions

    private func sendMessage() async {
        if to.isEmpty { errorText = "Укажите хотя бы одного получателя"; return }
        let error = await vm.send(recipients: to, subject: subject, body: bodyText,
                                  attachments: attachments, isDraft: false)
        if error == nil { dismiss() } else { showSendDisabled = true }
    }

    private func saveDraft() async {
        let error = await vm.send(recipients: to, subject: subject, body: bodyText,
                                  attachments: attachments, isDraft: true)
        if error == nil { dismiss() } else { errorText = error }
    }

    private func loadSelectedPhotos() {
        let items = photoItems
        guard !items.isEmpty else { return }
        Task {
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    let stamp = Int(Date().timeIntervalSince1970)
                    let name = "photo_\(stamp)_\(attachments.count + 1).jpg"
                    attachments.append(Attachment(
                        fileName: name,
                        fileSize: Int64(data.count),
                        fileExtension: "jpg",
                        content: data.base64EncodedString()))
                }
            }
            photoItems = []
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url) else { continue }
                attachments.append(Attachment(
                    fileName: url.lastPathComponent,
                    fileSize: Int64(data.count),
                    fileExtension: url.pathExtension,
                    content: data.base64EncodedString()))
            }
        case .failure(let error):
            errorText = error.localizedDescription
        }
    }
}