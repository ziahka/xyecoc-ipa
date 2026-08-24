//
//  SettingsRepository.swift
//  XyecocMail
//

import Foundation

final class SettingsRepository {

    private let api: ApiClient
    private let keychain: KeychainManager

    init(api: ApiClient = .shared, keychain: KeychainManager = .shared) {
        self.api = api
        self.keychain = keychain
    }

    private var token: String { keychain.getToken() ?? "" }

    // MARK: - Account Profile & Passwords

    /// account/profile — returns user account details, 2FA status, signatures, and reserve email.
    func getProfile() async -> ApiResponse {
        await api.request(RequestPayload(service: "account", action: "profile", token: token))
    }

    /// account/update-password — changes the account password.
    func updatePassword(old: String, new: String) async -> ApiResponse {
        let payload = RequestPayload(
            service: "account",
            action: "update-password",
            token: token,
            data: .object([
                "password_old": .string(old),
                "password_new": .string(new)
            ])
        )
        return await api.request(payload)
    }

    /// account/reserve-email — attaches or updates the recovery email.
    func updateReserveEmail(password: String, reserveEmail: String) async -> ApiResponse {
        let payload = RequestPayload(
            service: "account",
            action: "reserve-email",
            token: token,
            data: .object([
                "password": .string(password),
                "email": .string(reserveEmail)
            ])
        )
        return await api.request(payload)
    }

    // MARK: - 2FA Management

    /// account/2fa-qr — retrieves secret and QR payload for authenticator apps.
    func get2FAQR() async -> ApiResponse {
        await api.request(RequestPayload(service: "account", action: "2fa-qr", token: token))
    }

    /// account/2fa-update — activates 2FA using code and TOTP secret.
    func enable2FA(code: String, secret: String) async -> ApiResponse {
        let payload = RequestPayload(
            service: "account",
            action: "2fa-update",
            token: token,
            data: .object([
                "code": .string(code),
                "secret": .string(secret)
            ])
        )
        return await api.request(payload)
    }

    /// account/2fa-delete — disables two-factor authentication.
    func disable2FA(password: String) async -> ApiResponse {
        let payload = RequestPayload(
            service: "account",
            action: "2fa-delete",
            token: token,
            data: .object(["password": .string(password)])
        )
        return await api.request(payload)
    }

    // MARK: - Signatures & Aliases

    /// account/update-profile — saves default and reply signatures.
    func updateSignatures(reply: String, new: String) async -> ApiResponse {
        let payload = RequestPayload(
            service: "account",
            action: "update-profile",
            token: token,
            data: .object([
                "signature_reply": .string(reply),
                "signature_new": .string(new)
            ])
        )
        return await api.request(payload)
    }

    /// account/addresses — list of aliases for the current mailbox.
    func fetchAddresses() async -> ApiResponse {
        await api.request(RequestPayload(service: "account", action: "addresses", token: token))
    }

    /// account/register (additional = true) — creates a new alias.
    func createAlias(email: String, password: String) async -> ApiResponse {
        let payload = RequestPayload(
            service: "account",
            action: "register",
            token: token,
            data: .object([
                "email": .string(email),
                "password": .string(password),
                "password_repeat": .string(password),
                "additional": .bool(true)
            ])
        )
        return await api.request(payload)
    }

    /// mail/address-delete — removes an alias.
    func deleteAlias(email: String) async -> ApiResponse {
        let payload = RequestPayload(
            service: "mail",
            action: "address-delete",
            token: token,
            data: .object(["email": .string(email)])
        )
        return await api.request(payload)
    }

    // MARK: - Folders & Tags CRUD

    /// mail/folder-new — creates a custom folder.
    func createFolder(name: String) async -> ApiResponse {
        let payload = RequestPayload(
            service: "mail",
            action: "folder-new",
            token: token,
            data: .object(["name": .string(name)])
        )
        return await api.request(payload)
    }

    /// mail/folder-delete — removes a custom folder.
    func deleteFolder(name: String) async -> ApiResponse {
        let payload = RequestPayload(
            service: "mail",
            action: "folder-delete",
            token: token,
            data: .object(["name": .string(name)])
        )
        return await api.request(payload)
    }

    /// mail/tag-new — creates a color tag.
    func createTag(name: String, colorHex: String) async -> ApiResponse {
        let payload = RequestPayload(
            service: "mail",
            action: "tag-new",
            token: token,
            data: .object([
                "name": .string(name),
                "color": .string(colorHex)
            ])
        )
        return await api.request(payload)
    }

    /// mail/tag-delete — removes a tag.
    func deleteTag(id: Int64) async -> ApiResponse {
        let payload = RequestPayload(
            service: "mail",
            action: "tag-delete",
            token: token,
            data: .object(["id": .int(id)])
        )
        return await api.request(payload)
    }

    // MARK: - Feedback & Account Deletion

    /// admin/feedback-new — sends support ticket or bug report.
    func sendFeedback(type: String, subject: String, message: String) async -> ApiResponse {
        let payload = RequestPayload(
            service: "admin",
            action: "feedback-new",
            token: token,
            data: .object([
                "type": .string(type),
                "subject": .string(subject),
                "message": .string(message)
            ])
        )
        return await api.request(payload)
    }

    /// account/delete — permanently deletes the mailbox.
    func deleteAccount(password: String) async -> ApiResponse {
        let payload = RequestPayload(
            service: "account",
            action: "delete",
            token: token,
            data: .object(["password": .string(password)])
        )
        return await api.request(payload)
    }
}