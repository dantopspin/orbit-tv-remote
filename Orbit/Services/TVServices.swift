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

    @discardableResult
    func addOrUpdate(_ device: TVDevice) -> TVDevice {
        if let index = matchingIndex(for: device) {
            let previous = devices[index]
            let merged = merge(
                previous,
                with: device
            )
            devices[index] = merged
            selectedDeviceID = merged.id
            persist()
            return merged
        }

        devices.append(device)
        selectedDeviceID = device.id
        persist()
        return device
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
        merged.formDiscoveryAliases(
            previous.discoveryAliases
        )

        if oldDeviceID != resolvedDevice.id,
           !Self.isProvisionalIdentity(
               oldDeviceID,
               platform: previous.platform,
               host: previous.host
           ) {
            merged.formDiscoveryAliases(
                [oldDeviceID]
            )
        }

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

        if UserDefaults.standard.string(
            forKey: AppSettings.Keys.freeDeviceID
        ) == oldDeviceID {
            UserDefaults.standard.set(
                merged.id,
                forKey: AppSettings.Keys.freeDeviceID
            )
        }

        persist()
    }

    @discardableResult
    func refreshKnownDevices(
        from discoveredDevices: [TVDevice]
    ) -> Set<String> {
        var endpointChanges: Set<String> = []
        var didChange = false

        for discovered in discoveredDevices {
            guard let index = matchingIndex(
                for: discovered
            ) else {
                continue
            }

            let previous = devices[index]
            let merged = merge(
                previous,
                with: discovered
            )

            if previous.host != merged.host ||
                effectivePort(
                    for: previous
                ) != effectivePort(
                    for: merged
                ) {
                endpointChanges.insert(previous.id)
            }

            if previous != merged {
                devices[index] = merged
                didChange = true
            }
        }

        if didChange {
            persist()
        }

        return endpointChanges
    }

    private func matchingIndex(
        for incoming: TVDevice
    ) -> Int? {
        if let exact = devices.firstIndex(
            where: { $0.id == incoming.id }
        ) {
            return exact
        }

        let incomingAliases =
            incoming.discoveryAliases.union(
                [incoming.id]
            )

        return devices.firstIndex { saved in
            guard saved.platform ==
                    incoming.platform else {
                return false
            }

            let savedAliases =
                saved.discoveryAliases.union(
                    [saved.id]
                )

            return !savedAliases.isDisjoint(
                with: incomingAliases
            )
        }
    }

    private func merge(
        _ previous: TVDevice,
        with incoming: TVDevice
    ) -> TVDevice {
        var merged = previous
        merged.host = incoming.host
        merged.port = incoming.port ?? previous.port

        merged.formDiscoveryAliases(
            previous.discoveryAliases
                .union(
                    incoming.discoveryAliases
                )
        )

        if previous.id != incoming.id {
            merged.formDiscoveryAliases(
                [incoming.id]
            )
        }

        let genericNames: Set<String> = [
            "Smart TV",
            "Roku",
            "Roku TV",
            "Samsung TV",
            "LG TV",
            "Android TV",
            "Fire TV",
            previous.platform.displayName
        ]

        if genericNames.contains(previous.name),
           !incoming.name.isEmpty {
            merged.name = incoming.name
        }

        if merged.capabilities.isEmpty,
           !incoming.capabilities.isEmpty {
            merged.capabilities = incoming.capabilities
        }

        return merged
    }

    private func effectivePort(
        for device: TVDevice
    ) -> Int? {
        device.port ??
            Self.defaultPort(
                for: device.platform
            )
    }

    private static func defaultPort(
        for platform: TVPlatform
    ) -> Int? {
        switch platform {
        case .roku:
            return 8060
        case .samsung:
            return 8002
        case .lgWebOS:
            return 3001
        case .androidTV:
            return 6466
        case .fireTV:
            return 8080
        default:
            return nil
        }
    }

    private static func isProvisionalIdentity(
        _ id: String,
        platform: TVPlatform,
        host: String
    ) -> Bool {
        let prefix: String

        switch platform {
        case .roku:
            prefix = "roku"
        case .samsung:
            prefix = "samsung"
        case .lgWebOS:
            prefix = "lg"
        case .androidTV:
            prefix = "androidtv"
        case .fireTV:
            prefix = "firetv"
        default:
            return false
        }

        return id.lowercased() ==
            "\(prefix)-\(host.lowercased())"
    }

    func remove(_ device: TVDevice) {
        let wasFreeDevice =
            UserDefaults.standard.string(
                forKey: AppSettings.Keys.freeDeviceID
            ) == device.id

        devices.removeAll {
            $0.id == device.id
        }

        if selectedDeviceID == device.id {
            selectedDeviceID = devices.first?.id
        }

        if wasFreeDevice {
            if let selectedDeviceID {
                UserDefaults.standard.set(
                    selectedDeviceID,
                    forKey: AppSettings.Keys.freeDeviceID
                )
            } else {
                UserDefaults.standard.removeObject(
                    forKey: AppSettings.Keys.freeDeviceID
                )
            }
        }

        PairingCredentialStore.remove(
            platform: device.platform,
            deviceID: device.id
        )
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
final class TVAdapterEventEmitter {
    private var generation = 0
    private var continuation:
        AsyncStream<TVAdapterEvent>.Continuation?

    var stream: AsyncStream<TVAdapterEvent> {
        generation += 1
        let currentGeneration = generation

        continuation?.finish()

        let pair = AsyncStream<TVAdapterEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        continuation = pair.continuation

        pair.continuation.onTermination = {
            [weak self] _ in

            Task { @MainActor in
                guard let self,
                      self.generation == currentGeneration else {
                    return
                }

                self.continuation = nil
            }
        }

        return pair.stream
    }

    func yield(_ event: TVAdapterEvent) {
        continuation?.yield(event)
    }

    func finish() {
        generation += 1
        continuation?.finish()
        continuation = nil
    }
}

@MainActor
protocol TVControlling: AnyObject {
    var device: TVDevice { get }
    var events: AsyncStream<TVAdapterEvent> { get }

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
    var events: AsyncStream<TVAdapterEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

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
    case transport(String)
    case permissionDenied(String)
    case rejected(status: Int?, message: String?)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .unsupported:
            return "This control is not supported by the connected TV."
        case .unreachable:
            return "The TV could not be reached on your local network."
        case .transport(let message):
            return message
        case .permissionDenied(let message):
            return message
        case .rejected(_, let message):
            return message ?? "The TV rejected that command."
        case .invalidResponse:
            return "The TV returned an unexpected response."
        }
    }

    var affectsConnectionState: Bool {
        switch self {
        case .unreachable, .transport:
            return true
        case .unsupported, .permissionDenied, .rejected, .invalidResponse:
            return false
        }
    }
}

enum TVPlatformAvailability {
    static func isEnabled(_ platform: TVPlatform) -> Bool {
        switch platform {
        case .roku, .fireTV:
            #if DEBUG
            return true
            #else
            return false
            #endif

        default:
            return true
        }
    }
}

@MainActor
enum TVAdapterFactory {
    static func makeAdapter(for device: TVDevice) -> TVControlling {
        guard TVPlatformAvailability.isEnabled(device.platform) else {
            return UnsupportedTVAdapter(device: device)
        }

        switch device.platform {
        case .roku:
            return RokuAdapter(device: device)
        case .samsung:
            return SamsungTizenAdapter(device: device)
        case .lgWebOS:
            return LGWebOSAdapter(device: device)
        case .androidTV:
            return AndroidTVAdapter(device: device)
        case .fireTV:
            return FireTVAdapter(device: device)
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
    @ObservationIgnored var onDevicesUpdated:
        (([TVDevice]) -> Void)?

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
                guard let device = self.device(from: response),
                      TVPlatformAvailability.isEnabled(device.platform) else {
                    continue
                }
                discovered[device.id] = device
            }

            for device in androidDevices
            where TVPlatformAvailability.isEnabled(device.platform) {
                discovered[device.id] = device
            }

            self.devices = discovered.values.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            self.onDevicesUpdated?(self.devices)
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
            var androidCandidate = TVDevice(
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

            if let discoveredAlias = devices.first(
                where: {
                    $0.platform == .androidTV &&
                    $0.host == trimmed &&
                    $0.id != androidCandidate.id
                }
            )?.id {
                androidCandidate.formDiscoveryAliases(
                    [discoveredAlias]
                )
            }

            devices.removeAll {
                $0.id == androidCandidate.id
            }
            devices.append(androidCandidate)
            return androidCandidate
        }

        if TVPlatformAvailability.isEnabled(.fireTV) {
            let fireCandidate = TVDevice(
                id: "firetv-\(trimmed)",
                name: "Fire TV",
                platform: .fireTV,
                host: trimmed,
                port: 8080,
                capabilities: [
                    .directionalNavigation,
                    .touchpad,
                    .keyboard,
                    .power,
                    .volume,
                    .mute,
                    .appLaunching,
                    .playback
                ]
            )

            let fireTV = FireTVAdapter(
                device: fireCandidate
            )

            if await fireTV.probeWakeEndpoint() {
                devices.removeAll {
                    $0.id == fireCandidate.id
                }
                devices.append(fireCandidate)
                return fireCandidate
            }
        }

        async let samsungHTTP = LocalTCPProbe.isReachable(
            host: trimmed,
            port: 8001
        )
        async let samsungSecure = LocalTCPProbe.isReachable(
            host: trimmed,
            port: 8002
        )
        async let lgPlain = LocalTCPProbe.isReachable(
            host: trimmed,
            port: 3000
        )
        async let lgSecure = LocalTCPProbe.isReachable(
            host: trimmed,
            port: 3001
        )

        let (
            samsungHTTPReachable,
            samsungSecureReachable,
            lgPlainReachable,
            lgSecureReachable
        ) = await (
            samsungHTTP,
            samsungSecure,
            lgPlain,
            lgSecure
        )

        if samsungHTTPReachable ||
            samsungSecureReachable {
            let samsungCandidate = TVDevice(
                id: "samsung-\(trimmed)",
                name: "Samsung TV",
                platform: .samsung,
                host: trimmed,
                port: 8002
            )

            let samsung = SamsungTizenAdapter(
                device: samsungCandidate
            )

            do {
                _ = try await samsung.connect()
                var connectedDevice = samsung.device

                if let discoveredAlias = devices.first(
                    where: {
                        $0.platform == .samsung &&
                        $0.host == trimmed &&
                        $0.id != connectedDevice.id
                    }
                )?.id {
                    connectedDevice.formDiscoveryAliases(
                        [discoveredAlias]
                    )
                }

                await samsung.disconnect()

                devices.removeAll {
                    $0.id == connectedDevice.id
                }
                devices.append(connectedDevice)
                return connectedDevice
            } catch TVControlError.permissionDenied(
                let message
            ) {
                lastError = message
                return nil
            } catch {
                await samsung.disconnect()
            }
        }

        if lgPlainReachable ||
            lgSecureReachable {
            let lgCandidate = TVDevice(
                id: "lg-\(trimmed)",
                name: "LG TV",
                platform: .lgWebOS,
                host: trimmed,
                port: 3001
            )

            let lg = LGWebOSAdapter(
                device: lgCandidate
            )

            do {
                _ = try await lg.connect()
                var connectedDevice = lg.device

                if let discoveredAlias = devices.first(
                    where: {
                        $0.platform == .lgWebOS &&
                        $0.host == trimmed &&
                        $0.id != connectedDevice.id
                    }
                )?.id {
                    connectedDevice.formDiscoveryAliases(
                        [discoveredAlias]
                    )
                }

                await lg.disconnect()

                devices.removeAll {
                    $0.id == connectedDevice.id
                }
                devices.append(connectedDevice)
                return connectedDevice
            } catch TVControlError.permissionDenied(
                let message
            ) {
                lastError = message
                return nil
            } catch {
                await lg.disconnect()
            }
        }

        if TVPlatformAvailability.isEnabled(.roku) {
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
                // Continue to the generic unsupported result below.
            }
        }

        lastError = "Orbit couldn’t identify a supported TV at that address."
        return nil
    }

    private func device(from response: SSDPResponse) -> TVDevice? {
        guard let host = response.location.host else { return nil }

        let discoveryIdentity =
            response.canonicalUSN ??
            host.lowercased()

        switch response.platformHint {
        case .roku:
            return TVDevice(
                id: "roku-\(discoveryIdentity)",
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
                id: "samsung-\(discoveryIdentity)",
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
                id: "lg-\(discoveryIdentity)",
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

        case .fireTV:
            return TVDevice(
                id: "firetv-\(discoveryIdentity)",
                name: "Fire TV",
                platform: .fireTV,
                host: host,
                port: 8080,
                capabilities: [
                    .directionalNavigation,
                    .touchpad,
                    .keyboard,
                    .power,
                    .volume,
                    .mute,
                    .appLaunching,
                    .playback
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

    func refreshEntitlements() async {
        var active = false
        let now = Date()

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? verified(result) else {
                continue
            }

            let isOrbitSubscription = [
                Self.weeklyID,
                Self.monthlyID
            ].contains(transaction.productID)

            let isNotExpired =
                transaction.expirationDate.map {
                    $0 > now
                } ?? true

            if isOrbitSubscription,
               transaction.revocationDate == nil,
               !transaction.isUpgraded,
               isNotExpired {
                active = true
                break
            }
        }

        #if DEBUG
        if UserDefaults.standard.bool(
            forKey: AppSettings.Keys.premiumOverride
        ) {
            active = true
        }
        #endif

        isPremium = active

        if active {
            purchasePending = false
        }
    }

    private func observeTransactions() -> Task<Void, Never> {
        Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                if let transaction = try? self.verified(update) {
                    await transaction.finish()
                    self.purchasePending = false
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
    private var pendingCoalescedCommands:
        Set<RemoteCommand> = []
    private var generation = 0

    @discardableResult
    func enqueue(
        command: RemoteCommand,
        coalescing: Bool,
        _ operation: @escaping @MainActor () async -> Void
    ) -> Bool {
        if coalescing,
           pendingCoalescedCommands.contains(
               command
           ) {
            return false
        }

        if coalescing {
            pendingCoalescedCommands.insert(
                command
            )
        }

        let previous = tail
        let currentGeneration = generation

        let next = Task { @MainActor [weak self] in
            if let previous {
                await previous.value
            }

            guard let self else { return }

            defer {
                if self.generation ==
                    currentGeneration,
                   coalescing {
                    self.pendingCoalescedCommands.remove(
                        command
                    )
                }
            }

            guard !Task.isCancelled,
                  self.generation ==
                    currentGeneration else {
                return
            }

            await operation()
        }

        tail = next
        return true
    }

    func enqueueAndWait(
        _ operation: @escaping @MainActor () async throws -> Void
    ) async throws {
        let previous = tail
        let currentGeneration = generation

        let resultTask = Task {
            @MainActor () -> Result<Void, Error> in

            if let previous {
                await previous.value
            }

            guard !Task.isCancelled,
                  self.generation == currentGeneration else {
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
        generation += 1
        tail?.cancel()
        tail = nil
        pendingCoalescedCommands.removeAll()
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
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var connectingDeviceID: String?
    @ObservationIgnored private var wasBackgrounded = false
    @ObservationIgnored private let commandQueue = RemoteCommandQueue()

    init() {
        KeychainStore.prepareForCurrentInstall()

        if UserDefaults.standard.string(
            forKey: AppSettings.Keys.freeDeviceID
        ) == nil,
        let selectedID = deviceStore.selectedDeviceID {
            UserDefaults.standard.set(
                selectedID,
                forKey: AppSettings.Keys.freeDeviceID
            )
        }

        discovery.onDevicesUpdated = {
            [weak self] discoveredDevices in

            guard let self else { return }

            let movedDeviceIDs =
                self.deviceStore.refreshKnownDevices(
                    from: discoveredDevices
                )

            guard let currentID =
                    self.currentDevice?.id,
                  movedDeviceIDs.contains(
                      currentID
                  ) else {
                return
            }

            self.refreshSelection()
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
            case .fireTV:
                if requiresPairing {
                    return "Enter the 4-digit code shown on your Fire TV."
                }
                return "Connecting to Fire TV…"
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
        reconnectTask?.cancel()
        eventTask?.cancel()
        connectingDeviceID = nil
        commandQueue.cancel()

        let previousAdapter = adapter

        let storedDevice =
            deviceStore.addOrUpdate(device)

        if purchases.isPremium ||
            UserDefaults.standard.string(
                forKey: AppSettings.Keys.freeDeviceID
            ) == nil {
            UserDefaults.standard.set(
                storedDevice.id,
                forKey: AppSettings.Keys.freeDeviceID
            )
        }

        let replacement =
            TVAdapterFactory.makeAdapter(
                for: storedDevice
            )
        adapter = replacement
        currentCapabilities =
            storedDevice.capabilities
        pairingRequirement = .none
        lastControlError = nil

        Task { @MainActor [weak self, previousAdapter, replacement] in
            await previousAdapter?.disconnect()

            guard let self,
                  self.adapter === replacement else {
                return
            }

            self.connect()
        }
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
        guard let device = currentDevice else {
            adapter = nil
            connectionState = .connecting
            currentCapabilities = []
            pairingRequirement = .none
            return
        }

        if connectingDeviceID == device.id,
           connectionState == .connecting {
            return
        }

        connectTask?.cancel()

        if adapter?.device.id != device.id {
            commandQueue.cancel()

            let previousAdapter = adapter
            let replacement = TVAdapterFactory.makeAdapter(for: device)
            adapter = replacement

            Task {
                await previousAdapter?.disconnect()
            }
        }

        guard let adapter else { return }

        let deviceID = device.id
        connectingDeviceID = deviceID
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
                self.connectingDeviceID = nil

                if case .none = connection.pairingRequirement {
                    self.startEventMonitoring(
                        adapter: adapter,
                        deviceID: resolvedDevice.id
                    )
                }
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
                self.connectingDeviceID = nil
            }
        }
    }

    func appDidBecomeActive() {
        Task { @MainActor [weak self] in
            await self?.purchases.refreshEntitlements()
        }

        guard currentDevice != nil else {
            wasBackgrounded = false
            return
        }

        let shouldReconnect =
            wasBackgrounded ||
            connectionState == .connecting ||
            connectionState == .unavailable

        wasBackgrounded = false

        if !requiresPairing,
           shouldReconnect {
            connect()
        }
    }

    func appDidEnterBackground() {
        wasBackgrounded = true
        connectTask?.cancel()
        connectTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        eventTask?.cancel()
        eventTask = nil
        connectingDeviceID = nil
        commandQueue.cancel()

        guard let activeAdapter = adapter else {
            return
        }

        connectionState = .connecting

        Task {
            await activeAdapter.disconnect()
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

            startEventMonitoring(
                adapter: adapter,
                deviceID: resolvedDevice.id
            )
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

        let deviceID = adapter.device.id

        let accepted = commandQueue.enqueue(
            command: command,
            coalescing:
                command.coalescesWhilePending
        ) { [weak self, adapter] in
            guard let self,
                  self.currentDevice?.id == deviceID else {
                return
            }

            do {
                try await adapter.send(command)

                guard self.currentDevice?.id == deviceID else {
                    return
                }

                self.lastControlError = nil
                self.connectionState = .connected
            } catch is CancellationError {
                return
            } catch {
                guard self.currentDevice?.id == deviceID else {
                    return
                }

                self.applyControlError(error)
            }
        }

        if accepted {
            Haptics.shared.tap()
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
            applyControlError(error)
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
            applyControlError(error)
        }
    }

    func forgetCurrentDevice() {
        guard let device = currentDevice else { return }

        connectTask?.cancel()
        connectTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        eventTask?.cancel()
        eventTask = nil
        connectingDeviceID = nil
        commandQueue.cancel()

        let previousAdapter = adapter
        adapter = nil

        favorites.removeAll(for: device.id)
        deviceStore.remove(device)

        Task { @MainActor [weak self, previousAdapter] in
            await previousAdapter?.disconnect()

            guard let self else { return }

            if self.currentDevice != nil {
                self.refreshSelection()
            } else {
                self.connectionState = .connecting
                self.currentCapabilities = []
                self.pairingRequirement = .none
                self.lastControlError = nil
            }
        }
    }

    func refreshSelection() {
        connectTask?.cancel()
        connectTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        eventTask?.cancel()
        eventTask = nil
        connectingDeviceID = nil
        commandQueue.cancel()

        let previousAdapter = adapter
        let replacement = currentDevice.map(TVAdapterFactory.makeAdapter)
        adapter = replacement
        currentCapabilities = currentDevice?.capabilities ?? []
        pairingRequirement = .none
        lastControlError = nil

        Task { @MainActor [weak self, previousAdapter, replacement] in
            await previousAdapter?.disconnect()

            guard let self else { return }

            if let replacement,
               self.adapter === replacement,
               self.currentDevice != nil {
                self.connect()
            } else if self.currentDevice == nil {
                self.connectionState = .connecting
            }
        }
    }

    private func startEventMonitoring(
        adapter: TVControlling,
        deviceID: String
    ) {
        eventTask?.cancel()

        let stream = adapter.events

        eventTask = Task { @MainActor [weak self, adapter] in
            for await event in stream {
                guard !Task.isCancelled,
                      let self,
                      self.adapter === adapter,
                      self.currentDevice?.id == deviceID else {
                    return
                }

                self.handleAdapterEvent(
                    event,
                    adapter: adapter,
                    deviceID: deviceID
                )
            }
        }
    }

    private func handleAdapterEvent(
        _ event: TVAdapterEvent,
        adapter: TVControlling,
        deviceID: String
    ) {
        switch event {
        case .disconnected(let message):
            connectionState = .unavailable
            lastControlError = message ??
                "The TV connection was interrupted."
            scheduleReconnect(
                adapter: adapter,
                deviceID: deviceID
            )

        case .powerStateChanged(let state):
            connectionState = state

        case .pairingRevoked(let message):
            reconnectTask?.cancel()
            connectionState = .unavailable
            lastControlError = message ??
                "The TV no longer recognizes Orbit. Pair it again."
        }
    }

    private func scheduleReconnect(
        adapter: TVControlling,
        deviceID: String
    ) {
        reconnectTask?.cancel()

        reconnectTask = Task { @MainActor [weak self, adapter] in
            try? await Task.sleep(
                nanoseconds: 1_500_000_000
            )

            guard !Task.isCancelled,
                  let self,
                  self.adapter === adapter,
                  self.currentDevice?.id == deviceID,
                  !self.requiresPairing else {
                return
            }

            self.connect()
        }
    }

    private func applyControlError(_ error: Error) {
        lastControlError = error.localizedDescription

        if let controlError = error as? TVControlError {
            if controlError.affectsConnectionState {
                connectionState = .unavailable
            }
            return
        }

        connectionState = .unavailable
    }
}
