//
//  SettingsRepository.swift
//  XyecocMail
//
//  Minimal port of the `account`-service settings calls needed by Compose
//  (profile signature + sender aliases). The full settings surface (2FA,
//  folders/tags/filters, password, aliases CRUD) lands in Milestone 5;
//  this stub intentionally covers only what Compose consumes.
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

    /// account/profile — used for the signature appended to outgoing mail.
    func getProfile() async -> ApiResponse {
        await api.request(RequestPayload(service: "account", action: "profile", token: token))
    }

    /// account/addresses — sender aliases shown in the Compose "От:" picker.
    /// (Milestone 5 will also persist these into the local cache.)
    func fetchAddresses() async -> ApiResponse {
        await api.request(RequestPayload(service: "account", action: "addresses", token: token))
    }
}
