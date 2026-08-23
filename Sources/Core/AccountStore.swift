//
//  AccountStore.swift
//  XyecocMail
//
//  Observable coordinator for multi-account support (up to 15 mailboxes).
//  Owns the notion of "which account is active", keeps the published list in
//  sync with the Keychain, and switches the isolated `MailDatabase` cache when
//  the active account changes.
//

import SwiftUI

@MainActor
final class AccountStore: ObservableObject {

    @Published private(set) var emails: [String] = []
    @Published private(set) var activeEmail: String?

    private let keychain = KeychainManager.shared

    static let maxAccounts = KeychainManager.maxAccounts

    init() { reload() }

    var canAddAccount: Bool { emails.count < Self.maxAccounts }

    /// Re-read the current list + active account from the Keychain.
    func reload() {
        emails = keychain.accounts()
        activeEmail = keychain.activeEmail()
    }

    /// Called after a successful login/registration (the repository already
    /// stored the token and set the active email in the Keychain).
    func onLoggedIn() async {
        let active = keychain.activeEmail() ?? "default"
        await MailDatabase.shared.activate(account: active)
        reload()
    }

    /// Ensure the on-disk cache matches the active account at launch.
    func syncActiveCache() async {
        guard let active = activeEmail else { return }
        await MailDatabase.shared.activate(account: active)
    }

    /// Switch to another already-stored account.
    func setActive(_ email: String) async {
        guard email != activeEmail else { return }
        keychain.setActiveEmail(email)
        await MailDatabase.shared.activate(account: email)
        reload()
    }

    /// Remove an account. If it was active, the next account is promoted; if
    /// none remain, `activeEmail` becomes nil and the app returns to login.
    func remove(_ email: String) async {
        keychain.removeAccount(email: email)
        await MailDatabase.shared.deleteCache(forAccount: email)
        if let active = keychain.activeEmail() {
            await MailDatabase.shared.activate(account: active)
        }
        reload()
    }

    /// Log out of the currently active account.
    func logoutActive() async {
        guard let active = activeEmail else { return }
        await remove(active)
    }
}
