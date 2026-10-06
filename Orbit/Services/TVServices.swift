import Foundation
import SwiftUI
import StoreKit
import UIKit
import Observation

@MainActor
@Observable
final class DeviceStore {
    private(set) var devices: [TVDevice] = []
    var selectedDeviceID: String?

    init() { load() }

    var selectedDevice: TVDevice? {
        devices.first { $0.id == selectedDeviceID }
    }

    func addOrUpdate(_ device: TVDevice) {
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            devices[index] = device
        } else {
            devices.append(device)
        }
        selectedDeviceID = device.id
        persist()
    }

    func select(_ device: TVDevice) {
        selectedDeviceID = device.id
        persist()
    }

    func rename(_ device: TVDevice, to name: String) {
        guard let index = devices.firstIndex(where: { $0.id == device.id }) else { return }
        devices[index].name = name
        persist()
    }

    func remove(_ device: TVDevice) {
        devices.removeAll { $0.id == device.id }
        if selectedDeviceID == device.id { selectedDeviceID = devices.first?.id }
        KeychainStore.remove("pairing.\(device.id)")
        persist()
    }

    private func load() {
        selectedDeviceID = UserDefaults.standard.string(forKey: AppSettings.Keys.selectedDeviceID)
        guard let data = UserDefaults.standard.data(forKey: AppSettings.Keys.savedDevices),
              let decoded = try? JSONDecoder().decode([TVDevice].self, from: data) else { return }

        devices = decoded

        if selectedDevice == nil {
            selectedDeviceID = devices.first?.id
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(devices) {
            UserDefaults.standard.set(data, forKey: AppSettings.Keys.savedDevices)
        }
        UserDefaults.standard.set(selectedDeviceID, forKey: AppSettings.Keys.selectedDeviceID)
    }
}

protocol TVControlling: AnyObject {
    var device: TVDevice { get }
    func probe() async -> Bool
    func send(_ command: RemoteCommand) async throws
    func send(text: String) async throws
    func apps() async throws -> [TVApp]
    func inputs() async throws -> [TVInput]
    func launch(app: TVApp) async throws
    func select(input: TVInput) async throws
}

enum TVControlError: LocalizedError {
    case unsupported
    case unreachable
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .unsupported: return "This control is not supported by the connected TV."
        case .unreachable: return "The TV could not be reached on your local network."
        case .invalidResponse: return "The TV returned an unexpected response."
        }
    }
}

enum TVAdapterFactory {
    static func makeAdapter(for device: TVDevice) -> TVControlling {
        switch device.platform {
        case .roku:
            return RokuAdapter(device: device)
        default:
            return UnsupportedTVAdapter(device: device)
        }
    }
}

final class UnsupportedTVAdapter: TVControlling {
    let device: TVDevice

    init(device: TVDevice) { self.device = device }

    func probe() async -> Bool { false }
    func send(_ command: RemoteCommand) async throws { throw TVControlError.unsupported }
    func send(text: String) async throws { throw TVControlError.unsupported }
    func apps() async throws -> [TVApp] { [] }
    func inputs() async throws -> [TVInput] { [] }
    func launch(app: TVApp) async throws { throw TVControlError.unsupported }
    func select(input: TVInput) async throws { throw TVControlError.unsupported }
}

@MainActor
@Observable
final class DiscoveryService {
    private(set) var devices: [TVDevice] = []
    private(set) var isSearching = false
    var lastError: String?

    func startScan() {
        isSearching = true
        lastError = nil
        devices = []

        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if !Task.isCancelled { isSearching = false }
        }
    }

    func stopScan() {
        isSearching = false
    }

    func addManualRoku(host: String) async -> TVDevice? {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        isSearching = true
        lastError = nil
        defer { isSearching = false }

        let candidate = TVDevice(
            id: "roku-\(trimmed)",
            name: "Roku TV",
            platform: .roku,
            host: trimmed,
            port: 8060,
            capabilities: [
                .directionalNavigation, .keyboard, .power, .volume, .mute,
                .inputSelection, .appLaunching, .playback, .channels
            ]
        )

        let adapter = RokuAdapter(device: candidate)
        if await adapter.probe() {
            devices.removeAll { $0.id == candidate.id }
            devices.append(candidate)
            return candidate
        }

        lastError = "No compatible Roku device responded at that address."
        return nil
    }
}

@MainActor
@Observable
final class PurchaseManager {
    static let weeklyID = "orbit.weekly"
    static let monthlyID = "orbit.monthly"

    private(set) var products: [Product] = []
    private(set) var isPremium = false
    private(set) var isLoading = false
    var errorMessage: String?

    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = observeTransactions()
        Task { await refresh() }
    }

    deinit {
        updatesTask?.cancel()
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            products = try await Product.products(for: [Self.weeklyID, Self.monthlyID])
                .sorted { lhs, rhs in
                    if lhs.id == rhs.id { return false }
                    return lhs.id == Self.weeklyID
                }
            await refreshEntitlements()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func purchase(_ product: Product) async {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try verified(verification)
                await transaction.finish()
                await refreshEntitlements()
            case .pending, .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func product(id: String) -> Product? {
        products.first { $0.id == id }
    }

    private func refreshEntitlements() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? verified(result) else { continue }
            if [Self.weeklyID, Self.monthlyID].contains(transaction.productID),
               transaction.revocationDate == nil {
                active = true
            }
        }

        #if DEBUG
        if UserDefaults.standard.bool(forKey: AppSettings.Keys.premiumOverride) {
            active = true
        }
        #endif

        isPremium = active
    }

    private func observeTransactions() -> Task<Void, Never> {
        Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                if let transaction = try? self.verified(update) {
                    await transaction.finish()
                    await self.refreshEntitlements()
                }
            }
        }
    }

    private func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe): return safe
        case .unverified: throw StoreError.failedVerification
        }
    }

    enum StoreError: Error {
        case failedVerification
    }
}

@MainActor
@Observable
final class AppModel {
    var connectionState: TVConnectionState = .connecting
    var lastControlError: String?

    let deviceStore = DeviceStore()
    let discovery = DiscoveryService()
    let purchases = PurchaseManager()

    @ObservationIgnored private var adapter: TVControlling?

    var currentDevice: TVDevice? {
        deviceStore.selectedDevice
    }

    func select(_ device: TVDevice) {
        deviceStore.addOrUpdate(device)
        adapter = TVAdapterFactory.makeAdapter(for: device)
        connect()
    }

    func connect() {
        guard let device = currentDevice else {
            adapter = nil
            connectionState = .connecting
            return
        }

        if adapter?.device.id != device.id {
            adapter = TVAdapterFactory.makeAdapter(for: device)
        }

        guard let adapter else { return }
        connectionState = .connecting

        Task {
            let reachable = await adapter.probe()
            connectionState = reachable ? .connected : .unavailable
        }
    }

    func send(_ command: RemoteCommand) {
        guard let adapter else { return }

        Haptics.shared.tap()

        Task {
            do {
                try await adapter.send(command)
                if connectionState != .connected {
                    connectionState = .connected
                }
            } catch {
                lastControlError = error.localizedDescription
                connectionState = .unavailable
            }
        }
    }

    func send(text: String) async throws {
        guard let adapter else { throw TVControlError.unreachable }
        try await adapter.send(text: text)
    }

    func apps() async -> [TVApp] {
        guard let adapter else { return [] }
        return (try? await adapter.apps()) ?? []
    }

    func inputs() async -> [TVInput] {
        guard let adapter else { return [] }
        return (try? await adapter.inputs()) ?? []
    }

    func launch(_ app: TVApp) async {
        try? await adapter?.launch(app: app)
    }

    func select(_ input: TVInput) async {
        try? await adapter?.select(input: input)
    }

    func forgetCurrentDevice() {
        guard let device = currentDevice else { return }

        deviceStore.remove(device)
        adapter = nil

        if currentDevice != nil {
            refreshSelection()
        } else {
            connectionState = .connecting
        }
    }

    func refreshSelection() {
        adapter = currentDevice.map(TVAdapterFactory.makeAdapter)

        if currentDevice != nil {
            connect()
        } else {
            connectionState = .connecting
        }
    }
}
