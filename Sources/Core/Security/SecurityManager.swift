import Foundation
import CryptoKit
import LocalAuthentication

@MainActor
final class SecurityManager: ObservableObject {
    static let shared = SecurityManager()

    private let pinKeychainKey = "app_security_pin_hash"

    @Published var isLocked: Bool = false

    private init() {
        self.isLocked = (SecurityManager.readPinHashFromKeychain(key: "app_security_pin_hash") != nil)
    }

    var hasPin: Bool {
        getPinHash() != nil
    }

    var isBiometricsAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    var biometricType: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return "Биометрия"
        }
    }

    var biometricIconName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        default: return "lock.shield"
        }
    }

    func authenticateWithBiometrics() async -> Bool {
        guard isBiometricsAvailable else { return false }
        let context = LAContext()
        context.localizedCancelTitle = "Ввести PIN"
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Разблокировка почтового ящика"
            )
            if success {
                self.isLocked = false
                return true
            }
            return false
        } catch {
            return false
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
        isLocked = false
        objectWillChange.send()
    }

    func emergencyReset() {
        deletePinHash()
        isLocked = false
        objectWillChange.send()
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