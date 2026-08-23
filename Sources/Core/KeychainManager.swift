//
//  KeychainManager.swift
//  XyecocMail
//
//  iOS replacement for Android `util/SecurePrefs.kt` (EncryptedSharedPreferences).
//  Stores the auth token and email as generic-password Keychain items. No
//  third-party dependencies — only the system `Security` framework.
//
//  Accessibility is `AfterFirstUnlock` so the token survives reboots and can be
//  read by a future background-refresh task, but not before the first unlock.
//

import Foundation
import Security

final class KeychainManager {

    static let shared = KeychainManager()

    private let service = "com.xyecoc.mail"
    private let tokenKey = "auth_token"     // same logical key as SecurePrefs
    private let emailKey = "user_email"

    private init() {}

    // MARK: - Low-level SecItem access

    @discardableResult
    private func set(_ value: String?, account: String) -> Bool {
        // Always delete first to keep writes idempotent (upsert semantics).
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)

        guard let value = value, let data = value.data(using: .utf8) else {
            return true // nil value == cleared
        }

        var attributes = base
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    private func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Public API (mirrors SecurePrefs)

    func saveToken(_ token: String?) { set(token, account: tokenKey) }
    func getToken() -> String? { get(account: tokenKey) }

    func saveEmail(_ email: String?) { set(email, account: emailKey) }
    func getEmail() -> String? { get(account: emailKey) }

    /// Equivalent to `SecurePrefs.clear()` on logout.
    func clear() {
        set(nil, account: tokenKey)
        set(nil, account: emailKey)
    }

    var isLoggedIn: Bool { !(getToken() ?? "").isEmpty }
}
