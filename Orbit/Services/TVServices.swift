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

    func updateCapabilities(for deviceID: String, capabilities: Set<TVCapability>) {
        guard let index = devices.firstIndex(where: { $0.id == deviceID }) else { return }
        guard devices[index].capabilities != capabilities else { return }

        devices[index].capabilities = capabilities
        persist()
    }

    func rename(_ device: TVDevice, to name: String) {
        guard let index = devices.firstIndex(where: { $0.id == device.id }) else { return }
        devices[index].name = name
        persist()
    }

    func reconcile(oldDeviceID: String, with resolvedDevice: TVDevice) {
        guard let oldIndex = devices.firstIndex(where: { $0.id == oldDeviceID }) else {
            addOrUpdate(resolvedDevice)
            return
        }

        let previous = devices[oldIndex]
        let genericNames: Set<String> = [
            "Roku TV",
            "Smart TV",
            previous.platform.displayName
        ]

        var merged = resolvedDevice
        merged.roomName = previous.roomName

        if !genericNames.contains(previous.name) {
            merged.name = previous.name
        }

        devices.removeAll { $0.id == resolvedDevice.id && $0.id != oldDeviceID }

        guard let refreshedIndex = devices.firstIndex(where: { $0.id == oldDeviceID }) else {
            addOrUpdate(merged)
            return
        }

        devices[refreshedIndex] = merged

        if selectedDeviceID == oldDeviceID {
            selectedDeviceID = merged.id
        }

        persist()
    }

    func remove(_ device: TVDevice) {
        devices.removeAll { $0.id == device.id }
        if selectedDeviceID == device.id { selectedDeviceID = devices.first?.id }
        PairingCredentialStore.remove(platform: device.platform, deviceID: device.id)
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

@MainActor
protocol TVControlling: AnyObject {
    var device: TVDevice { get }

    func connect() async throws -> TVConnectionInfo
    func disconnect() async

    func pairingRequirement() async throws -> TVPairingRequirement
    func pair(using response: TVPairingResponse) async throws

    func send(_ command: RemoteCommand) async throws
    func beginPress(_ command: RemoteCommand) async throws
    func endPress(_ command: RemoteCommand) async throws
    func send(text: String) async throws

    func apps() async throws -> [TVApp]
    func inputs() async throws -> [TVInput]
    func launch(app: TVApp) async throws
    func select(input: TVInput) async throws
}

extension TVControlling {
    func disconnect() async {}

    func pairingRequirement() async throws -> TVPairingRequirement {
        .none
    }

    func pair(using response: TVPairingResponse) async throws {
        guard case .none = try await pairingRequirement() else {
            throw TVControlError.unsupported
        }
    }

    func beginPress(_ command: RemoteCommand) async throws {
        try await send(command)
    }

    func endPress(_ command: RemoteCommand) async throws {}
}

enum TVControlError: LocalizedError {
    case unsupported
    case unreachable
    case permissionDenied(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .unsupported:
            return "This control is not supported by the connected TV."
        case .unreachable:
            return "The TV could not be reached on your local network."
        case .permissionDenied(let message):
            return message
        case .invalidResponse:
            return "The TV returned an unexpected response."
        }
    }
}

@MainActor
enum TVAdapterFactory {
    static func makeAdapter(for device: TVDevice) -> TVControlling {
        switch device.platform {
        case .roku:
            return RokuAdapter(device: device)
        case .samsung:
            return SamsungTizenAdapter(device: device)
        case .lgWebOS:
            return LGWebOSAdapter(device: device)
        default:
            return UnsupportedTVAdapter(device: device)
        }
    }
}

final class UnsupportedTVAdapter: TVControlling {
    let device: TVDevice

    init(device: TVDevice) { self.device = device }

    func connect() async throws -> TVConnectionInfo { throw TVControlError.unsupported }
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

    func addManualTV(host: String) async -> TVDevice? {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)

        guard isValidLocalIPv4Address(trimmed) else {
            lastError = "Enter a valid local IPv4 address, for example 192.168.1.24."
            return nil
        }

        isSearching = true
        lastError = nil
        defer { isSearching = false }

        let samsungCandidate = TVDevice(
            id: "samsung-\(trimmed)",
            name: "Samsung TV",
            platform: .samsung,
            host: trimmed,
            port: 8002
        )

        let samsung = SamsungTizenAdapter(device: samsungCandidate)

        do {
            _ = try await samsung.connect()
            let connectedDevice = samsung.device

            devices.removeAll { $0.id == connectedDevice.id }
            devices.append(connectedDevice)
            return connectedDevice
        } catch TVControlError.permissionDenied(let message) {
            lastError = message
            return nil
        } catch {
            await samsung.disconnect()
        }

        let lgCandidate = TVDevice(
            id: "lg-\(trimmed)",
            name: "LG TV",
            platform: .lgWebOS,
            host: trimmed,
            port: 3001
        )

        let lg = LGWebOSAdapter(device: lgCandidate)

        do {
            _ = try await lg.connect()
            let connectedDevice = lg.device

            devices.removeAll { $0.id == connectedDevice.id }
            devices.append(connectedDevice)
            return connectedDevice
        } catch TVControlError.permissionDenied(let message) {
            lastError = message
            return nil
        } catch {
            await lg.disconnect()
        }

        let rokuCandidate = TVDevice(
            id: "roku-\(trimmed)",
            name: "Roku TV",
            platform: .roku,
            host: trimmed,
            port: 8060
        )

        let roku = RokuAdapter(device: rokuCandidate)

        do {
            _ = try await roku.connect()
            let connectedDevice = roku.device

            devices.removeAll { $0.id == connectedDevice.id }
            devices.append(connectedDevice)
            return connectedDevice
        } catch {
            lastError = "Orbit couldn’t identify a supported TV at that address."
            return nil
        }
    }

    private func isValidLocalIPv4Address(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }

        let octets = parts.compactMap { part -> Int? in
            guard !part.isEmpty,
                  part.count <= 3,
                  part.allSatisfy({ $0.isNumber }),
                  let number = Int(part),
                  (0...255).contains(number) else {
                return nil
            }

            return number
        }

        guard octets.count == 4 else { return false }

        if octets[0] == 10 { return true }
        if octets[0] == 172 && (16...31).contains(octets[1]) { return true }
        if octets[0] == 192 && octets[1] == 168 { return true }
        if octets[0] == 169 && octets[1] == 254 { return true }
        if octets[0] == 100 && (64...127).contains(octets[1]) { return true }

        return false
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
private final class RemoteCommandQueue {
    private var tail: Task<Void, Never>?

    func enqueue(_ operation: @escaping @MainActor () async -> Void) {
        let previous = tail

        let next = Task { @MainActor in
            if let previous {
                await previous.value
            }

            guard !Task.isCancelled else { return }
            await operation()
        }

        tail = next
    }

    func enqueueAndWait(_ operation: @escaping @MainActor () async throws -> Void) async throws {
        let previous = tail

        let resultTask = Task { @MainActor () -> Result<Void, Error> in
            if let previous {
                await previous.value
            }

            guard !Task.isCancelled else {
                return .failure(CancellationError())
            }

            do {
                try await operation()
                return .success(())
            } catch {
                return .failure(error)
            }
        }

        tail = Task { @MainActor in
            _ = await resultTask.value
        }

        switch await resultTask.value {
        case .success:
            return
        case .failure(let error):
            throw error
        }
    }

    func cancel() {
        tail?.cancel()
        tail = nil
    }
}

@MainActor
@Observable
final class AppModel {
    var connectionState: TVConnectionState = .connecting
    var currentCapabilities: Set<TVCapability> = []
    var pairingRequirement: TVPairingRequirement = .none
    var lastControlError: String?

    let deviceStore = DeviceStore()
    let discovery = DiscoveryService()
    let purchases = PurchaseManager()

    @ObservationIgnored private var adapter: TVControlling?
    @ObservationIgnored private var connectTask: Task<Void, Never>?
    @ObservationIgnored private let commandQueue = RemoteCommandQueue()

    init() {
        KeychainStore.prepareForCurrentInstall()
    }

    var currentDevice: TVDevice? {
        deviceStore.selectedDevice
    }

    func select(_ device: TVDevice) {
        connectTask?.cancel()
        commandQueue.cancel()

        deviceStore.addOrUpdate(device)
        adapter = TVAdapterFactory.makeAdapter(for: device)
        currentCapabilities = device.capabilities
        pairingRequirement = .none
        lastControlError = nil
        connect()
    }

    func connect() {
        connectTask?.cancel()

        guard let device = currentDevice else {
            adapter = nil
            connectionState = .connecting
            currentCapabilities = []
            pairingRequirement = .none
            return
        }

        if adapter?.device.id != device.id {
            commandQueue.cancel()
            adapter = TVAdapterFactory.makeAdapter(for: device)
        }

        guard let adapter else { return }

        let deviceID = device.id
        connectionState = .connecting
        lastControlError = nil

        connectTask = Task { @MainActor [weak self, adapter] in
            do {
                let connection = try await adapter.connect()

                guard !Task.isCancelled,
                      let self,
                      self.currentDevice?.id == deviceID else {
                    return
                }

                let resolvedDevice = adapter.device
                self.deviceStore.reconcile(
                    oldDeviceID: deviceID,
                    with: resolvedDevice
                )

                self.connectionState = connection.state
                self.currentCapabilities = connection.capabilities
                self.pairingRequirement = connection.pairingRequirement
                self.lastControlError = nil
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled,
                      let self,
                      self.currentDevice?.id == deviceID else {
                    return
                }

                self.connectionState = .unavailable
                self.currentCapabilities = []
                self.pairingRequirement = .none
                self.lastControlError = error.localizedDescription
            }
        }
    }

    func appDidBecomeActive() {
        guard currentDevice != nil else { return }
        connect()
    }

    func send(_ command: RemoteCommand) {
        guard let adapter else { return }

        Haptics.shared.tap()
        let deviceID = adapter.device.id

        commandQueue.enqueue { [weak self, adapter] in
            guard let self,
                  self.currentDevice?.id == deviceID else {
                return
            }

            do {
                try await adapter.send(command)

                guard self.currentDevice?.id == deviceID else { return }

                self.lastControlError = nil
                self.connectionState = .connected
            } catch is CancellationError {
                return
            } catch {
                guard self.currentDevice?.id == deviceID else { return }

                self.lastControlError = error.localizedDescription
                self.connectionState = .unavailable
            }
        }
    }

    func send(text: String) async throws {
        guard let adapter else { throw TVControlError.unreachable }

        let deviceID = adapter.device.id

        try await commandQueue.enqueueAndWait { [weak self, adapter] in
            guard let self,
                  self.currentDevice?.id == deviceID else {
                throw CancellationError()
            }

            try await adapter.send(text: text)

            guard self.currentDevice?.id == deviceID else {
                throw CancellationError()
            }

            self.lastControlError = nil
            self.connectionState = .connected
        }
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
        guard let adapter else { return }

        do {
            try await commandQueue.enqueueAndWait {
                try await adapter.launch(app: app)
            }
            lastControlError = nil
            connectionState = .connected
        } catch is CancellationError {
            return
        } catch {
            lastControlError = error.localizedDescription
            connectionState = .unavailable
        }
    }

    func select(_ input: TVInput) async {
        guard let adapter else { return }

        do {
            try await commandQueue.enqueueAndWait {
                try await adapter.select(input: input)
            }
            lastControlError = nil
            connectionState = .connected
        } catch is CancellationError {
            return
        } catch {
            lastControlError = error.localizedDescription
            connectionState = .unavailable
        }
    }

    func forgetCurrentDevice() {
        guard let device = currentDevice else { return }

        connectTask?.cancel()
        commandQueue.cancel()
        deviceStore.remove(device)
        adapter = nil

        if currentDevice != nil {
            refreshSelection()
        } else {
            connectionState = .connecting
            currentCapabilities = []
            pairingRequirement = .none
            lastControlError = nil
        }
    }

    func refreshSelection() {
        connectTask?.cancel()
        commandQueue.cancel()
        adapter = currentDevice.map(TVAdapterFactory.makeAdapter)
        currentCapabilities = currentDevice?.capabilities ?? []
        pairingRequirement = .none
        lastControlError = nil

        if currentDevice != nil {
            connect()
        } else {
            connectionState = .connecting
        }
    }
}
