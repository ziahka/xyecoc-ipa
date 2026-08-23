//
//  KeychainManager.swift
//  XyecocMail
//
//  Multi-account secure storage (up to 15 mailboxes). Each account's token is a
//  separate generic-password Keychain item keyed by email; an index item holds
//  the ordered list of emails and another marks the active account.
//
//  Backwards-compatible convenience accessors (`getToken`/`getEmail`) resolve to
//  the currently active account, so the rest of the app is unaffected.
//

import Foundation
import Security

final class KeychainManager {

    static let shared = KeychainManager()
    static let maxAccounts = 15

    private let service = "com.xyecoc.mail"
    private let indexKey = "accounts_index"   // JSON [String] of emails, insertion order
    private let activeKey = "active_email"
    private func tokenKey(_ email: String) -> String { "token:\(email)" }

    private init() {}

    // MARK: - Low-level SecItem access

    @discardableResult
    private func set(_ value: String?, account: String) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)
        guard let value = value, let data = value.data(using: .utf8) else { return true }
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

    // MARK: - Account index

    /// Ordered list of stored account emails.
    func accounts() -> [String] {
        guard let json = get(account: indexKey),
              let data = json.data(using: .utf8),
              let list = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return list
    }

    private func saveIndex(_ emails: [String]) {
        guard let data = try? JSONEncoder().encode(emails),
              let json = String(data: data, encoding: .utf8) else { return }
        set(json, account: indexKey)
    }

    // MARK: - Active account

    func activeEmail() -> String? { get(account: activeKey) }
    func setActiveEmail(_ email: String?) { set(email, account: activeKey) }

    // MARK: - Tokens

    func token(forEmail email: String) -> String? { get(account: tokenKey(email)) }

    func activeToken() -> String? {
        guard let email = activeEmail() else { return nil }
        return token(forEmail: email)
    }

    /// Add a new account or update an existing one's token.
    /// Returns `false` only when adding a *new* account would exceed the limit.
    @discardableResult
    func upsertAccount(email: String, token: String) -> Bool {
        var list = accounts()
        if !list.contains(email) {
            guard list.count < Self.maxAccounts else { return false }
            list.append(email)
            saveIndex(list)
        }
        set(token, account: tokenKey(email))
        return true
    }

    /// Refresh the token of the currently active account (used by refresh-token).
    func updateActiveToken(_ token: String) {
        guard let email = activeEmail() else { return }
        set(token, account: tokenKey(email))
    }

    func removeAccount(email: String) {
        set(nil, account: tokenKey(email))
        var list = accounts()
        list.removeAll { $0 == email }
        saveIndex(list)
        if activeEmail() == email {
            setActiveEmail(list.first)   // promote next account, or clear
        }
    }

    func clearAll() {
        for email in accounts() { set(nil, account: tokenKey(email)) }
        set(nil, account: indexKey)
        set(nil, account: activeKey)
    }

    // MARK: - Convenience (active account) — keeps existing call sites working

    func getToken() -> String? { activeToken() }
    func getEmail() -> String? { activeEmail() }
    var isLoggedIn: Bool { !(activeToken() ?? "").isEmpty }
    var canAddAccount: Bool { accounts().count < Self.maxAccounts }
}
