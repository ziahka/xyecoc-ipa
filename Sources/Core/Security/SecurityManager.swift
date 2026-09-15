import Foundation
import CryptoKit
import CommonCrypto
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
        let saved = savePinHash(Self.saltedPinHash(for: pin))
        if saved {
            objectWillChange.send()
        }
        return saved
    }

    func verifyPin(_ pin: String) -> Bool {
        refreshLockout()
        guard !isInLockout else { return false }
        guard let stored = getPinHash() else {
            isLocked = false
            return true
        }
        let isValid: Bool
        if let parsed = Self.parseSaltedHash(stored) {
            isValid = Self.saltedPinHash(pin: pin, salt: parsed.salt, rounds: parsed.rounds) == parsed.hashHex
        } else {
            // Старый формат без соли: проверяем голым SHA-256 и при успехе
            // прозрачно перезаписываем на PBKDF2.
            isValid = (Self.sha256Hex(pin) == stored)
            if isValid {
                _ = savePinHash(Self.saltedPinHash(for: pin))
            }
        }
        if isValid {
            clearFailedAttempts()
            isLocked = false
        } else {
            registerFailedAttempt()
        }
        return isValid
    }

    func removePin() {
        deletePinHash()
        clearFailedAttempts()
        isLocked = false
        objectWillChange.send()
    }

    func emergencyReset() {
        deletePinHash()
        clearFailedAttempts()
        isLocked = false
        objectWillChange.send()
    }

    // MARK: - PIN brute-force protection

    private static let failedAttemptsKey = "pin_failed_attempts"
    private static let lockoutUntilKey = "pin_lockout_until"
    private static let maxFreeAttempts = 5
    private static let baseLockoutSeconds = 30
    private static let maxLockoutSeconds = 900

    /// Остаток блокировки в секундах; 0 — ввод PIN разрешён.
    @Published private(set) var lockoutRemaining: Int = 0

    var isInLockout: Bool { lockoutRemaining > 0 }

    /// Пересчитывает обратный отсчёт от сохранённого дедлайна.
    func refreshLockout() {
        let until = UserDefaults.standard.double(forKey: Self.lockoutUntilKey)
        guard until > 0 else {
            lockoutRemaining = 0
            return
        }
        lockoutRemaining = max(0, Int((until - Date().timeIntervalSince1970).rounded(.up)))
    }

    private func registerFailedAttempt() {
        let count = UserDefaults.standard.integer(forKey: Self.failedAttemptsKey) + 1
        UserDefaults.standard.set(count, forKey: Self.failedAttemptsKey)
        guard count >= Self.maxFreeAttempts else { return }
        // 30с, 60с, 120с… с потолком в 15 минут.
        let overshoot = min(count - Self.maxFreeAttempts, 6)
        let seconds = min(Self.maxLockoutSeconds, Self.baseLockoutSeconds << overshoot)
        UserDefaults.standard.set(Date().timeIntervalSince1970 + Double(seconds),
                                  forKey: Self.lockoutUntilKey)
        refreshLockout()
    }

    private func clearFailedAttempts() {
        UserDefaults.standard.removeObject(forKey: Self.failedAttemptsKey)
        UserDefaults.standard.removeObject(forKey: Self.lockoutUntilKey)
        lockoutRemaining = 0
    }

    // MARK: - Auto-lock

    /// Момент ухода приложения в фон; нужен для задержки блокировки.
    private var backgroundedAt: Date?

    func appDidEnterBackground() {
        backgroundedAt = Date()
    }

    /// Вызывается при возврате в активное состояние: блокирует, если фон
    /// длился дольше, чем разрешает настройка «Блокировать» (app_autolock).
    func appDidBecomeActive() {
        defer { backgroundedAt = nil }
        guard hasPin else { return }
        guard let backgroundedAt else {
            // Информации о фоне нет (сбой процесса в фоне) — блокируем.
            isLocked = true
            return
        }
        if Date().timeIntervalSince(backgroundedAt) >= AutoLockDelay.current.seconds {
            isLocked = true
        }
    }

    // MARK: - Crypto & Keychain

    private static let pinHashRounds: UInt32 = 250_000

    /// PBKDF2-SHA256 со случайной 16-байтной солью. Формат хранения:
    /// "v2|<rounds>|<saltHex>|<hashHex>".
    private static func saltedPinHash(for pin: String) -> String {
        var salt = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, salt.count, &salt)
        if status != errSecSuccess {
            // Криптографический RNG недоступен (редкий сбой): системный
            // генератор Swift на Apple-платформах тоже криптостойкий.
            salt = (0..<16).map { _ in UInt8.random(in: .min ... .max) }
        }
        return saltedPinHash(pin: pin, salt: salt, rounds: pinHashRounds)
    }

    private static func saltedPinHash(pin: String, salt: [UInt8], rounds: UInt32) -> String {
        let hash = pbkdf2(pin, salt: salt, rounds: rounds) ?? Data()
        return "v2|\(rounds)|\(hex(Data(salt)))|\(hex(hash))"
    }

    private static func parseSaltedHash(_ stored: String) -> (salt: [UInt8], rounds: UInt32, hashHex: String)? {
        let parts = stored.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 4, parts[0] == "v2",
              let rounds = UInt32(parts[1]),
              let salt = dataFromHex(String(parts[2])) else { return nil }
        return (salt, rounds, String(parts[3]))
    }

    private static func pbkdf2(_ pin: String, salt: [UInt8], rounds: UInt32) -> Data? {
        var derived = [UInt8](repeating: 0, count: 32)
        let pass = Array(pin.utf8)
        let status = CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            pass, pass.count,
            salt, salt.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
            rounds,
            &derived, derived.count)
        guard status == kCCSuccess else { return nil }
        return Data(derived)
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private static func dataFromHex(_ hexString: String) -> [UInt8]? {
        let chars = Array(hexString.utf8)
        guard !chars.isEmpty, chars.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(chars.count / 2)
        var index = 0
        while index < chars.count {
            guard let high = hexValue(chars[index]),
                  let low = hexValue(chars[index + 1]) else { return nil }
            bytes.append(high << 4 | low)
            index += 2
        }
        return bytes
    }

    private static func hexValue(_ ascii: UInt8) -> UInt8? {
        switch ascii {
        case 0x30...0x39: return ascii - 0x30
        case 0x61...0x66: return ascii - 0x61 + 10
        case 0x41...0x46: return ascii - 0x41 + 10
        default: return nil
        }
    }

    /// Старый формат PIN-хэша (без соли). Оставлен только для проверки
    /// и последующей миграции на PBKDF2 в verifyPin.
    private static func sha256Hex(_ input: String) -> String {
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

/// Задержка автоблокировки («app_autolock»): сколько времени после ухода в
/// фон приложение остаётся разблокированным при возврате. По умолчанию —
/// «Сразу», что повторяет прежнее поведение без настройки.
enum AutoLockDelay: String, CaseIterable, Identifiable {
    case immediately
    case oneMinute = "1min"
    case fiveMinutes = "5min"
    case fifteenMinutes = "15min"

    var id: String { rawValue }

    var seconds: TimeInterval {
        switch self {
        case .immediately: return 0
        case .oneMinute: return 60
        case .fiveMinutes: return 300
        case .fifteenMinutes: return 900
        }
    }

    var title: String {
        switch self {
        case .immediately: return "Сразу"
        case .oneMinute: return "Через минуту"
        case .fiveMinutes: return "Через 5 минут"
        case .fifteenMinutes: return "Через 15 минут"
        }
    }

    static var current: AutoLockDelay {
        AutoLockDelay(rawValue: UserDefaults.standard.string(forKey: "app_autolock") ?? "") ?? .immediately
    }
}