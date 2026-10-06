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
        case .androidTV:
            return AndroidTVAdapter(device: device)
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

    @ObservationIgnored private var scanTask: Task<Void, Never>?

    func startScan() {
        scanTask?.cancel()

        isSearching = true
        lastError = nil
        devices = []

        scanTask = Task { [weak self] in
            async let ssdpResponses = SSDPScanner.scan(
                timeout: 1.8
            )
            async let androidTVs = AndroidTVBonjourScanner.scan(
                timeout: 1.8
            )

            let (responses, androidDevices) = await (
                ssdpResponses,
                androidTVs
            )

            guard !Task.isCancelled, let self else { return }

            var discovered: [String: TVDevice] = [:]

            for response in responses {
                guard let device = self.device(from: response) else { continue }
                discovered[device.id] = device
            }

            for device in androidDevices {
                discovered[device.id] = device
            }

            self.devices = discovered.values.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            self.isSearching = false
        }
    }

    func stopScan() {
        scanTask?.cancel()
        scanTask = nil
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

        let androidPairingReachable = await LocalTCPProbe.isReachable(
            host: trimmed,
            port: 6467
        )
        let androidRemoteReachable = androidPairingReachable
            ? true
            : await LocalTCPProbe.isReachable(
                host: trimmed,
                port: 6466
            )

        if androidPairingReachable || androidRemoteReachable {
            let androidCandidate = TVDevice(
                id: "androidtv-\(trimmed)",
                name: "Android TV",
                platform: .androidTV,
                host: trimmed,
                port: 6466,
                capabilities: [
                    .directionalNavigation,
                    .touchpad,
                    .power,
                    .volume,
                    .mute,
                    .inputSelection,
                    .playback,
                    .channels
                ]
            )

            devices.removeAll {
                $0.id == androidCandidate.id
            }
            devices.append(androidCandidate)
            return androidCandidate
        }

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

    private func device(from response: SSDPResponse) -> TVDevice? {
        guard let host = response.location.host else { return nil }

        switch response.platformHint {
        case .roku:
            return TVDevice(
                id: "roku-\(response.usn ?? host)",
                name: "Roku",
                platform: .roku,
                host: host,
                port: response.location.port ?? 8060,
                capabilities: [
                    .directionalNavigation,
                    .touchpad,
                    .keyboard,
                    .appLaunching,
                    .playback
                ]
            )

        case .samsung:
            return TVDevice(
                id: "samsung-\(response.usn ?? host)",
                name: "Samsung TV",
                platform: .samsung,
                host: host,
                port: 8002,
                capabilities: [
                    .directionalNavigation,
                    .touchpad,
                    .keyboard,
                    .power,
                    .volume,
                    .mute,
                    .inputSelection,
                    .playback,
                    .channels
                ]
            )

        case .lgWebOS:
            return TVDevice(
                id: "lg-\(response.usn ?? host)",
                name: "LG TV",
                platform: .lgWebOS,
                host: host,
                port: 3001,
                capabilities: [
                    .directionalNavigation,
                    .touchpad,
                    .keyboard,
                    .power,
                    .volume,
                    .mute,
                    .inputSelection,
                    .appLaunching,
                    .playback,
                    .channels
                ]
            )

        default:
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
    private(set) var isPurchasing = false
    private(set) var purchasePending = false
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
        errorMessage = nil
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

    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        guard !isPurchasing else { return false }

        isPurchasing = true
        purchasePending = false
        errorMessage = nil
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try verified(verification)
                await transaction.finish()
                await refreshEntitlements()
                return isPremium

            case .pending:
                purchasePending = true
                return false

            case .userCancelled:
                return false

            @unknown default:
                return false
            }
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func restore() async {
        guard !isPurchasing else { return }

        isPurchasing = true
        purchasePending = false
        errorMessage = nil
        defer { isPurchasing = false }

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
final class RemoteCustomizationStore {
    var preferences: RemoteCustomizationPreferences {
        didSet { persist() }
    }

    init() {
        if let data = UserDefaults.standard.data(
            forKey: AppSettings.Keys.remoteCustomization
        ),
           let decoded = try? JSONDecoder().decode(
               RemoteCustomizationPreferences.self,
               from: data
           ) {
            preferences = decoded
        } else {
            preferences = RemoteCustomizationPreferences()
        }
    }

    func setDefaultMode(_ mode: RemoteControlMode) {
        preferences.defaultMode = mode
    }

    func setShowInput(_ value: Bool) {
        preferences.showInput = value
    }

    func setShowPlayback(_ value: Bool) {
        preferences.showPlayback = value
    }

    func setShowKeyboard(_ value: Bool) {
        preferences.showKeyboard = value
    }

    func setShowApps(_ value: Bool) {
        preferences.showApps = value
    }

    func reset() {
        preferences = RemoteCustomizationPreferences()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        UserDefaults.standard.set(data, forKey: AppSettings.Keys.remoteCustomization)
    }
}

@MainActor
@Observable
final class RemoteFavoritesStore {
    private(set) var favoritesByDevice: [String: [RemoteFavorite]] = [:]

    init() {
        guard let data = UserDefaults.standard.data(
            forKey: AppSettings.Keys.remoteFavorites
        ),
        let decoded = try? JSONDecoder().decode(
            [String: [RemoteFavorite]].self,
            from: data
        ) else {
            return
        }

        favoritesByDevice = decoded
    }

    func favorites(
        for deviceID: String,
        kind: RemoteFavoriteKind
    ) -> [RemoteFavorite] {
        (favoritesByDevice[deviceID] ?? []).filter { $0.kind == kind }
    }

    func contains(
        deviceID: String,
        kind: RemoteFavoriteKind,
        targetID: String
    ) -> Bool {
        favoritesByDevice[deviceID]?.contains {
            $0.kind == kind && $0.targetID == targetID
        } ?? false
    }

    func toggle(
        deviceID: String,
        favorite: RemoteFavorite
    ) {
        var items = favoritesByDevice[deviceID] ?? []

        if let index = items.firstIndex(where: {
            $0.kind == favorite.kind && $0.targetID == favorite.targetID
        }) {
            items.remove(at: index)
        } else {
            items.append(favorite)
        }

        favoritesByDevice[deviceID] = items
        persist()
    }

    func migrate(from oldDeviceID: String, to newDeviceID: String) {
        guard oldDeviceID != newDeviceID,
              let oldItems = favoritesByDevice.removeValue(forKey: oldDeviceID) else {
            return
        }

        var newItems = favoritesByDevice[newDeviceID] ?? []

        for item in oldItems where !newItems.contains(item) {
            newItems.append(item)
        }

        favoritesByDevice[newDeviceID] = newItems
        persist()
    }

    func removeAll(for deviceID: String) {
        guard favoritesByDevice.removeValue(forKey: deviceID) != nil else { return }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(favoritesByDevice) else { return }
        UserDefaults.standard.set(data, forKey: AppSettings.Keys.remoteFavorites)
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
    let customization = RemoteCustomizationStore()
    let favorites = RemoteFavoritesStore()

    @ObservationIgnored private var adapter: TVControlling?
    @ObservationIgnored private var connectTask: Task<Void, Never>?
    @ObservationIgnored private let commandQueue = RemoteCommandQueue()

    init() {
        KeychainStore.prepareForCurrentInstall()

        if UserDefaults.standard.string(forKey: AppSettings.Keys.freeDeviceID) == nil,
           let selectedID = deviceStore.selectedDeviceID {
            UserDefaults.standard.set(selectedID, forKey: AppSettings.Keys.freeDeviceID)
        }
    }

    var currentDevice: TVDevice? {
        deviceStore.selectedDevice
    }

    var requiresPairing: Bool {
        if case .none = pairingRequirement {
            return false
        }
        return true
    }

    var connectionMessage: String? {
        switch connectionState {
        case .connecting:
            switch currentDevice?.platform {
            case .samsung, .lgWebOS:
                return "Approve Orbit on your TV if asked."
            case .androidTV:
                if requiresPairing {
                    return "Enter the code shown on your TV."
                }
                return "Connecting to Android TV…"
            default:
                return nil
            }

        case .unavailable:
            return lastControlError

        case .connected, .off:
            return nil
        }
    }

    func select(_ device: TVDevice) {
        connectTask?.cancel()
        commandQueue.cancel()

        deviceStore.addOrUpdate(device)

        if purchases.isPremium ||
            UserDefaults.standard.string(forKey: AppSettings.Keys.freeDeviceID) == nil {
            UserDefaults.standard.set(device.id, forKey: AppSettings.Keys.freeDeviceID)
        }

        adapter = TVAdapterFactory.makeAdapter(for: device)
        currentCapabilities = device.capabilities
        pairingRequirement = .none
        lastControlError = nil
        connect()
    }

    func canUse(_ device: TVDevice) -> Bool {
        if purchases.isPremium {
            return true
        }

        let freeID = UserDefaults.standard.string(forKey: AppSettings.Keys.freeDeviceID)
        return freeID == nil || freeID == device.id
    }

    @discardableResult
    func activate(_ device: TVDevice) -> Bool {
        guard canUse(device) else {
            return false
        }

        if purchases.isPremium {
            UserDefaults.standard.set(device.id, forKey: AppSettings.Keys.freeDeviceID)
        }

        deviceStore.select(device)
        refreshSelection()
        return true
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
                self.favorites.migrate(
                    from: deviceID,
                    to: resolvedDevice.id
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

        if !requiresPairing {
            connect()
        }
    }

    @discardableResult
    func submitPairing(
        _ response: TVPairingResponse
    ) async -> Bool {
        guard let adapter,
              let currentDevice else {
            return false
        }

        lastControlError = nil

        do {
            try await adapter.pair(using: response)

            let resolvedDevice = adapter.device
            deviceStore.reconcile(
                oldDeviceID: currentDevice.id,
                with: resolvedDevice
            )
            favorites.migrate(
                from: currentDevice.id,
                to: resolvedDevice.id
            )

            pairingRequirement = .none
            currentCapabilities = resolvedDevice.capabilities
            connectionState = .connected
            lastControlError = nil
            return true
        } catch {
            lastControlError = error.localizedDescription
            return false
        }
    }

    func cancelPairing() {
        guard requiresPairing else { return }

        let activeAdapter = adapter

        pairingRequirement = .none
        connectionState = .unavailable
        lastControlError = "Pairing canceled. Reconnect when you’re ready."

        Task {
            await activeAdapter?.disconnect()
        }
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
        favorites.removeAll(for: device.id)
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
