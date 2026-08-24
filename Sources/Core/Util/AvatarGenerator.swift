//
//  AvatarGenerator.swift
//  XyecocMail
//

import SwiftUI

enum AvatarGenerator {
    
    /// Извлекает до 2 заглавных инициалов из имени/фамилии или логина email.
    static func initials(displayName: String, email: String = "") -> String {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !trimmedName.isEmpty {
            let parts = trimmedName.split(whereSeparator: { $0.isWhitespace })
                .map { String($0) }
                .filter { !$0.isEmpty }
            
            if parts.count >= 2,
               let firstChar = parts[0].first,
               let secondChar = parts[1].first {
                return "\(firstChar)\(secondChar)".uppercased()
            } else if let singleWord = parts.first {
                let cleanWord = singleWord.filter { $0.isLetter || $0.isNumber }
                if cleanWord.count >= 2 {
                    return String(cleanWord.prefix(2)).uppercased()
                } else if let firstChar = cleanWord.first {
                    return String(firstChar).uppercased()
                }
            }
        }
        
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedEmail.isEmpty {
            let loginPart = trimmedEmail.split(separator: "@").first.map(String.init) ?? trimmedEmail
            let cleanLogin = loginPart.filter { $0.isLetter || $0.isNumber }
            if cleanLogin.count >= 2 {
                return String(cleanLogin.prefix(2)).uppercased()
            } else if let firstChar = cleanLogin.first {
                return String(firstChar).uppercased()
            }
        }
        
        return "?"
    }
    
    /// Генерирует детерминированный пастельный цвет фона на основе djb2-хэша.
    static func backgroundColor(for key: String) -> Color {
        let cleaned = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleaned.isEmpty else {
            return Color(hue: 0.55, saturation: 0.45, brightness: 0.70)
        }
        
        // djb2 hash algorithm: hash = ((hash << 5) + hash) + c
        var hash: UInt64 = 5381
        for byte in cleaned.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        
        let hue = Double(hash % 360) / 360.0
        let saturation: Double = 0.42
        let brightness: Double = 0.68
        
        return Color(hue: hue, saturation: saturation, brightness: brightness)
    }
}