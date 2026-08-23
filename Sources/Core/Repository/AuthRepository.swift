//
//  AuthRepository.swift
//  XyecocMail
//
//  Port of the Kotlin `AuthRepository` (data/repository/Repositories.kt).
//  Builds the `account`-service RPC payloads and persists the auth token /
//  email to the Keychain on successful authentication. Room's
//  `db.clearAllTables()` calls are intentionally omitted here — the local
//  cache layer (GRDB/Core Data) is added in a later milestone.
//

import Foundation

final class AuthRepository {

    private let api: ApiClient
    private let keychain: KeychainManager

    init(api: ApiClient = .shared, keychain: KeychainManager = .shared) {
        self.api = api
        self.keychain = keychain
    }

    // MARK: - account/authorization

    func login(email: String, password: String) async -> ApiResponse {
        let payload = RequestPayload(
            service: "account",
            action: "authorization",
            data: .object(["email": .string(email), "password": .string(password)])
        )
        let response = await api.request(payload)
        if response.isSuccess(), let token = response.extractToken(), !token.isEmpty {
            keychain.saveToken(token)
            keychain.saveEmail(email)
        }
        return response
    }

    // MARK: - account/check-mailbox

    func checkMailbox(_ email: String) async -> ApiResponse {
        let payload = RequestPayload(
            service: "account",
            action: "check-mailbox",
            data: .object(["email": .string(email)])
        )
        return await api.request(payload)
    }

    // MARK: - account/register

    func register(email: String, password: String, isAdditional: Bool = false) async -> ApiResponse {
        var fields: [String: JSONValue] = [
            "email": .string(email),
            "password": .string(password),
            "password_repeat": .string(password)
        ]
        if isAdditional { fields["additional"] = .bool(true) }

        let payload = RequestPayload(
            service: "account",
            action: "register",
            data: .object(fields)
        )
        return await api.request(payload)
    }

    // MARK: - account/2fa-check (login-time verification)

    func verify2fa(email: String, password: String, secret: String, code: String) async -> ApiResponse {
        let payload = RequestPayload(
            service: "account",
            action: "2fa-check",
            data: .object([
                "email": .string(email),
                "password": .string(password),
                "secret": .string(secret),
                "code": .string(code),
                "remove_auth": .bool(false)
            ])
        )
        let response = await api.request(payload)
        if response.isSuccess(), let token = response.extractToken(), !token.isEmpty {
            keychain.saveToken(token)
            keychain.saveEmail(email)
        }
        return response
    }

    // MARK: - account/forgot-password

    func forgotPassword(email: String, reserveEmail: String?, supportMessage: String?) async -> ApiResponse {
        let payload = RequestPayload(
            service: "account",
            action: "forgot-password",
            data: .object([
                "email": .string(email),
                "reserve_email": .string(reserveEmail ?? ""),
                "forgot_support": .string(supportMessage ?? "")
            ])
        )
        return await api.request(payload)
    }

    // MARK: - account/refresh-token

    func refreshToken(_ expiredToken: String) async -> ApiResponse {
        let payload = RequestPayload(
            service: "account",
            action: "refresh-token",
            data: .object(["token": .string(expiredToken)])
        )
        let response = await api.request(payload)
        if response.isSuccess(), let token = response.extractToken(), !token.isEmpty {
            keychain.saveToken(token)
        }
        return response
    }

    // MARK: - logout

    func logout() {
        keychain.clear()
    }
}
