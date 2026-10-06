import Foundation
import SwiftUI
import UIKit
import Security

struct AppSettings {
    enum Keys {
        static let onboardingCompleted = "orbit.onboardingCompleted"
        static let darkMode = "orbit.darkMode"
        static let hapticsEnabled = "orbit.hapticsEnabled"
        static let keepScreenAwake = "orbit.keepScreenAwake"
        static let selectedDeviceID = "orbit.selectedDeviceID"
        static let savedDevices = "orbit.savedDevices"
        static let premiumOverride = "orbit.premiumOverride"
    }
}

extension Color {
    static let orbitBackground = Color(uiColor: .systemGroupedBackground)
    static let orbitSurface = Color(uiColor: .secondarySystemGroupedBackground)
    static let orbitSurfaceRaised = Color(uiColor: .tertiarySystemGroupedBackground)
    static let orbitSeparator = Color(uiColor: .separator).opacity(0.45)
    static let orbitPower = Color(red: 0.95, green: 0.20, blue: 0.18)
}

struct OrbitPressStyle: ButtonStyle {
    var cornerRadius: CGFloat = 22

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(configuration.isPressed ? Color.primary.opacity(0.09) : Color.clear)
            )
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
    }
}

struct OrbitPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color(uiColor: .systemBackground))
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.78 : 1))
            )
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
    }
}

@MainActor
final class Haptics {
    static let shared = Haptics()
    private init() {}

    func tap() {
        guard UserDefaults.standard.object(forKey: AppSettings.Keys.hapticsEnabled) as? Bool ?? true else { return }
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred(intensity: 0.65)
    }

    func selection() {
        guard UserDefaults.standard.object(forKey: AppSettings.Keys.hapticsEnabled) as? Bool ?? true else { return }
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }
}

struct KeychainStore {
    enum KeychainError: Error { case unexpectedStatus(OSStatus) }

    static func set(_ data: Data, for key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Orbit",
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    static func data(for key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Orbit",
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        return result as? Data
    }

    static func remove(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Orbit",
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
