import Foundation
import LocalAuthentication
import CryptoKit

@MainActor
final class SecurityManager: ObservableObject {
    static let shared = SecurityManager()

    private let pinKeychainKey = "app_security_pin_hash"
    private let biometryDefaultsKey = "app_security_biometry_enabled"

    @Published var isLocked: Bool = false
    @Published var isBiometryEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isBiometryEnabled, forKey: biometryDefaultsKey)
        }
    }

    private var isAuthenticating: Bool = false

    private init() {
        self.isBiometryEnabled = UserDefaults.standard.bool(forKey: biometryDefaultsKey)
        self.isLocked = (SecurityManager.readPinHashFromKeychain(key: "app_security_pin_hash") != nil)
    }

    var hasPin: Bool {
        getPinHash() != nil
    }

    var biometryType: LABiometryType {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType
    }

    var biometryTitle: String {
        switch biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return "Биометрия"
        }
    }

    func setPin(_ pin: String) -> Bool {
        guard pin.count == 4, pin.allSatisfy(\.isNumber) else { return false }
        let hash = sha256(pin)
        let saved = savePinHash(hash)
        if saved {
            objectWillChange.send()
        }
        return saved
    }

    func verifyPin(_ pin: String) -> Bool {
        guard let savedHash = getPinHash() else {
            isLocked = false
            return true
        }
        let inputHash = sha256(pin)
        let isValid = (inputHash == savedHash)
        if isValid {
            isLocked = false
        }
        return isValid
    }

    func removePin() {
        deletePinHash()
        isBiometryEnabled = false
        isLocked = false
        isAuthenticating = false
        objectWillChange.send()
    }

    func emergencyReset() {
        deletePinHash()
        isBiometryEnabled = false
        isLocked = false
        isAuthenticating = false
        UserDefaults.standard.removeObject(forKey: biometryDefaultsKey)
        objectWillChange.send()
    }

    func authenticateWithBiometry() async {
        guard isBiometryEnabled, hasPin, !isAuthenticating, isLocked else { return }

        isAuthenticating = true
        defer { isAuthenticating = false }

        let context = LAContext()
        context.localizedCancelTitle = "Ввести PIN-код"
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return
        }

        let reason = "Разблокируйте приложение с помощью \(biometryTitle)"

        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
            if success {
                self.isLocked = false
            }
        } catch {
            // Обработка отмены пользователем или системного прерывания без краша
        }
    }

    func lockAppIfNeeded() {
        if hasPin {
            isLocked = true
        }
    }

    // MARK: - Crypto & Keychain

    private func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hashed = SHA256.hash(data: data)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func savePinHash(_ hash: String) -> Bool {
        deletePinHash()
        let data = Data(hash.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: pinKeychainKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    private func getPinHash() -> String? {
        Self.readPinHashFromKeychain(key: pinKeychainKey)
    }

    private static func readPinHashFromKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deletePinHash() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: pinKeychainKey
        ]
        SecItemDelete(query as CFDictionary)
    }
}