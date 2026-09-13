import SwiftUI
import CryptoKit

struct AvatarView: View {
    let email: String
    let displayName: String
    let size: CGFloat

    init(email: String, displayName: String = "", size: CGFloat = 40) {
        self.email = email
        self.displayName = displayName
        self.size = size
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(deterministicGradient(for: email.isEmpty ? displayName : email))
                .frame(width: size, height: size)

            Text(extractInitials())
                .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }

    private func extractInitials() -> String {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            let parts = name.split { $0.isWhitespace || $0 == "." || $0 == "_" }
                .map(String.init)
                .filter { !$0.isEmpty }

            if parts.count >= 2,
               let first = parts[0].first,
               let second = parts[1].first {
                return "\(first)\(second)".uppercased()
            } else if let singleWord = parts.first {
                let cleanWord = singleWord.filter { $0.isLetter || $0.isNumber }
                if cleanWord.count >= 2 {
                    return String(cleanWord.prefix(2)).uppercased()
                } else if let firstChar = cleanWord.first {
                    return String(firstChar).uppercased()
                }
            }
        }

        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanEmail.isEmpty {
            let userPart = cleanEmail.split(separator: "@").first.map(String.init) ?? cleanEmail
            let components = userPart.split { character in
                character == "." || character == "_" || character == "-" || character.isWhitespace
            }.map(String.init).filter { !$0.isEmpty }

            if components.count >= 2,
               let firstChar = components[0].first,
               let secondChar = components[1].first {
                return "\(firstChar)\(secondChar)".uppercased()
            }

            if let singleWord = components.first {
                let lettersOnly = singleWord.filter { $0.isLetter || $0.isNumber }
                if lettersOnly.count >= 2 {
                    return String(lettersOnly.prefix(2)).uppercased()
                }
                if let firstChar = lettersOnly.first {
                    return String(firstChar).uppercased()
                }
            }
        }

        return "?"
    }

    private func deterministicGradient(for input: String) -> LinearGradient {
        let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            return LinearGradient(
                colors: [Color(hue: 0.55, saturation: 0.45, brightness: 0.70),
                         Color(hue: 0.60, saturation: 0.50, brightness: 0.60)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        let digest = SHA256.hash(data: Data(normalized.utf8))
        let bytes = Array(digest)

        let byte0 = bytes.indices.contains(0) ? bytes[0] : 100
        let byte1 = bytes.indices.contains(1) ? bytes[1] : 150
        let byte2 = bytes.indices.contains(2) ? bytes[2] : 200
        let byte3 = bytes.indices.contains(3) ? bytes[3] : 250

        let hueStart = Double(byte0) / 255.0
        let hueEnd = Double(byte1) / 255.0

        let saturationStart = 0.50 + (Double(byte2 % 25) / 100.0)
        let saturationEnd = 0.55 + (Double(byte3 % 25) / 100.0)

        let brightness: Double = 0.65

        let startColor = Color(hue: hueStart, saturation: saturationStart, brightness: brightness)
        let endColor = Color(hue: hueEnd, saturation: saturationEnd, brightness: brightness)

        return LinearGradient(
            colors: [startColor, endColor],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
