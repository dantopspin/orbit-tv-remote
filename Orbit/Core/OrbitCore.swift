import Foundation
import SwiftUI
import UIKit
import Security

struct AppSettings {
    enum Keys {
        static let onboardingCompleted = "orbit.onboardingCompleted"
        static let tvSetupDeferred = "orbit.tvSetupDeferred"
        static let darkMode = "orbit.darkMode"
        static let hapticsEnabled = "orbit.hapticsEnabled"
        static let keepScreenAwake = "orbit.keepScreenAwake"
        static let selectedDeviceID = "orbit.selectedDeviceID"
        static let savedDevices = "orbit.savedDevices"
        static let premiumOverride = "orbit.premiumOverride"
        static let installationInitialized = "orbit.installationInitialized"
        static let freeDeviceID = "orbit.freeDeviceID"
        static let remoteCustomization = "orbit.remoteCustomization"
        static let remoteFavorites = "orbit.remoteFavorites"
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
            .scaleEffect(
                configuration.isPressed
                ? 0.985
                : 1
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        configuration.isPressed
                        ? Color.primary.opacity(0.08)
                        : Color.clear
                    )
                    .allowsHitTesting(false)
            )
            .animation(
                .easeOut(duration: 0.10),
                value: configuration.isPressed
            )
    }
}

struct OrbitPrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = 54

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color(uiColor: .systemBackground))
            .frame(maxWidth: .infinity)
            .frame(height: height)
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
    enum KeychainError: Error {
        case unexpectedStatus(OSStatus)
    }

    private static var service: String {
        Bundle.main.bundleIdentifier ?? "com.dantopspin.orbitremote"
    }

    static func prepareForCurrentInstall() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: AppSettings.Keys.installationInitialized) else { return }

        removeAll()
        defaults.set(true, forKey: AppSettings.Keys.installationInitialized)
    }

    static func set(_ data: Data, for key: String) throws {
        let lookup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let updates: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(lookup as CFDictionary, updates as CFDictionary)

        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(updateStatus)
        }

        var add = lookup
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError.unexpectedStatus(addStatus)
        }
    }

    static func data(for key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }

        return result as? Data
    }

    static func setCodable<T: Encodable>(_ value: T, for key: String) throws {
        try set(JSONEncoder().encode(value), for: key)
    }

    static func codable<T: Decodable>(_ type: T.Type, for key: String) throws -> T? {
        guard let data = try data(for: key) else { return nil }
        return try JSONDecoder().decode(type, from: data)
    }

    static func remove(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }

    static func removeAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]

        SecItemDelete(query as CFDictionary)
    }
}

struct PairingCredentialStore {
    static func key(platform: TVPlatform, deviceID: String) -> String {
        "pairing.\(platform.rawValue).\(deviceID)"
    }

    static func save<T: Encodable>(
        _ credential: T,
        platform: TVPlatform,
        deviceID: String
    ) throws {
        try KeychainStore.setCodable(
            credential,
            for: key(platform: platform, deviceID: deviceID)
        )
    }

    static func load<T: Decodable>(
        _ type: T.Type,
        platform: TVPlatform,
        deviceID: String
    ) throws -> T? {
        try KeychainStore.codable(
            type,
            for: key(platform: platform, deviceID: deviceID)
        )
    }

    static func remove(platform: TVPlatform, deviceID: String) {
        KeychainStore.remove(key(platform: platform, deviceID: deviceID))
    }
}

