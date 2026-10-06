import Foundation
import Security
@preconcurrency import Network
@preconcurrency import AndroidTVRemoteControl

@MainActor
final class AndroidTVAdapter: TVControlling {
    private(set) var device: TVDevice

    private let serverKeyBox = AndroidTVServerKeyBox()
    private let eventEmitter = TVAdapterEventEmitter()

    var events: AsyncStream<TVAdapterEvent> {
        eventEmitter.stream
    }

    private var tlsManager: TLSManager?
    private var cryptoManager: CryptoManager?
    private var pairingManager: PairingManager?
    private var remoteManager: RemoteManager?
    private var pairingExpiryTask: Task<Void, Never>?
    private var remoteGeneration = 0

    init(device: TVDevice) {
        self.device = device
    }

    func connect() async throws -> TVConnectionInfo {
        try prepareProtocolManagersIfNeeded()

        if hasPairingMarker {
            do {
                try await connectRemote()
                return connectedInfo()
            } catch let error as TVControlError {
                guard case .permissionDenied = error else {
                    throw error
                }

                let pairingServiceReachable =
                    await LocalTCPProbe.isReachable(
                        host: device.host,
                        port: 6467,
                        timeout: 1.0
                    )

                guard pairingServiceReachable else {
                    throw TVControlError.transport(
                        "Android TV rejected the saved pairing identity, but its pairing service is not reachable yet. Make sure the TV is awake and try again."
                    )
                }

                PairingCredentialStore.remove(
                    platform: .androidTV,
                    deviceID: device.id
                )

                remoteGeneration += 1
                remoteManager?.stateChanged = nil
                remoteManager?.disconnect()
                remoteManager = nil
            }
        }

        let requirement = try await pairingRequirement()

        return TVConnectionInfo(
            state: .connecting,
            capabilities: capabilities,
            pairingRequirement: requirement
        )
    }

    func disconnect() async {
        pairingExpiryTask?.cancel()
        pairingExpiryTask = nil

        pairingManager?.stateChanged = nil
        pairingManager?.disconnect()
        pairingManager = nil

        remoteGeneration += 1
        remoteManager?.stateChanged = nil
        remoteManager?.disconnect()
        remoteManager = nil
    }

    func pairingRequirement() async throws -> TVPairingRequirement {
        try prepareProtocolManagersIfNeeded()

        if pairingManager != nil {
            return .pin(
                length: 6,
                message: "Enter the 6-character code shown on your TV."
            )
        }

        guard let tlsManager,
              let cryptoManager else {
            throw TVControlError.invalidResponse
        }

        let manager = PairingManager(
            tlsManager,
            cryptoManager
        )
        pairingManager = manager

        let gate = AndroidTVCallbackGate<TVPairingRequirement>()

        do {
            let requirement = try await withCheckedThrowingContinuation {
                (continuation:
                    CheckedContinuation<TVPairingRequirement, Error>) in

                gate.install(continuation)
                gate.fail(
                    after: 12,
                    with: TVControlError.transport(
                        "Android TV did not start pairing in time. Make sure it is awake and on the same Wi-Fi network."
                    )
                )

                manager.stateChanged = { state in
                    switch state {
                    case .waitingCode:
                        gate.succeed(
                            .pin(
                                length: 6,
                                message: "Enter the 6-character code shown on your TV."
                            )
                        )

                    case .error(let error):
                        gate.fail(
                            TVControlError.permissionDenied(
                                AndroidTVAdapter.userMessage(
                                    for: error
                                )
                            )
                        )

                    default:
                        break
                    }
                }

                manager.connect(
                    device.host,
                    "Orbit",
                    "atvremote",
                    timeout: 10
                )
            }

            schedulePairingExpiry()
            return requirement
        } catch {
            manager.disconnect()

            if pairingManager === manager {
                pairingManager = nil
            }

            throw error
        }
    }

    func pair(using response: TVPairingResponse) async throws {
        guard case .pin(let rawCode) = response else {
            throw TVControlError.permissionDenied(
                "Enter the code shown on your TV."
            )
        }

        let code = rawCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        guard code.count == 6,
              code.allSatisfy({
                  $0.isNumber || ("A"..."F").contains(String($0))
              }) else {
            throw TVControlError.permissionDenied(
                "The Android TV code must contain 6 hexadecimal characters."
            )
        }

        guard let manager = pairingManager else {
            throw TVControlError.permissionDenied(
                "Pairing expired. Start connecting to the TV again."
            )
        }

        pairingExpiryTask?.cancel()
        pairingExpiryTask = nil

        let gate = AndroidTVCallbackGate<Void>()

        do {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in

                gate.install(continuation)
                gate.fail(
                    after: 12,
                    with: TVControlError.permissionDenied(
                        "Android TV did not confirm the pairing code in time. Start pairing again."
                    )
                )

                manager.stateChanged = { state in
                    switch state {
                    case .successPaired:
                        gate.succeed(())

                    case .error(let error):
                        gate.fail(
                            TVControlError.permissionDenied(
                                AndroidTVAdapter.userMessage(
                                    for: error
                                )
                            )
                        )

                    default:
                        break
                    }
                }

                manager.sendSecret(code)
            }
        } catch {
            manager.stateChanged = nil
            manager.disconnect()

            if pairingManager === manager {
                pairingManager = nil
            }

            if case .permissionDenied =
                (error as? TVControlError),
               (try? await pairingRequirement()) != nil {
                throw TVControlError.permissionDenied(
                    "That code was not accepted. A new code is shown on your TV — enter the new code to try again."
                )
            }

            throw error
        }

        manager.stateChanged = nil
        manager.disconnect()
        pairingManager = nil

        try PairingCredentialStore.save(
            AndroidTVPairingMarker(),
            platform: .androidTV,
            deviceID: device.id
        )

        try await connectRemote()
    }

    func send(_ command: RemoteCommand) async throws {
        guard let manager = remoteManager else {
            throw TVControlError.unreachable
        }

        manager.send(
            KeyPress(
                try key(for: command),
                .SHORT
            )
        )
    }

    func beginPress(_ command: RemoteCommand) async throws {
        guard let manager = remoteManager else {
            throw TVControlError.unreachable
        }

        manager.send(
            KeyPress(
                try key(for: command),
                .START_LONG
            )
        )
    }

    func endPress(_ command: RemoteCommand) async throws {
        guard let manager = remoteManager else {
            throw TVControlError.unreachable
        }

        manager.send(
            KeyPress(
                try key(for: command),
                .END_LONG
            )
        )
    }

    func send(text: String) async throws {
        throw TVControlError.unsupported
    }

    func apps() async throws -> [TVApp] {
        []
    }

    func inputs() async throws -> [TVInput] {
        [
            TVInput(id: "source", name: "Source"),
            TVInput(id: "hdmi1", name: "HDMI 1"),
            TVInput(id: "hdmi2", name: "HDMI 2"),
            TVInput(id: "hdmi3", name: "HDMI 3"),
            TVInput(id: "hdmi4", name: "HDMI 4")
        ]
    }

    func launch(app: TVApp) async throws {
        throw TVControlError.unsupported
    }

    func select(input: TVInput) async throws {
        guard let manager = remoteManager else {
            throw TVControlError.unreachable
        }

        let key: Key

        switch input.id {
        case "source":
            key = .KEYCODE_TV_INPUT
        case "hdmi1":
            key = .KEYCODE_TV_INPUT_HDMI_1
        case "hdmi2":
            key = .KEYCODE_TV_INPUT_HDMI_2
        case "hdmi3":
            key = .KEYCODE_TV_INPUT_HDMI_3
        case "hdmi4":
            key = .KEYCODE_TV_INPUT_HDMI_4
        default:
            throw TVControlError.unsupported
        }

        manager.send(KeyPress(key))
    }

    private var capabilities: Set<TVCapability> {
        [
            .directionalNavigation,
            .touchpad,
            .power,
            .volume,
            .mute,
            .inputSelection,
            .playback,
            .channels
        ]
    }

    private var hasPairingMarker: Bool {
        (try? PairingCredentialStore.load(
            AndroidTVPairingMarker.self,
            platform: .androidTV,
            deviceID: device.id
        )) != nil
    }

    private func connectedInfo() -> TVConnectionInfo {
        TVConnectionInfo(
            state: .connected,
            capabilities: capabilities,
            pairingRequirement: .none
        )
    }

    private func prepareProtocolManagersIfNeeded() throws {
        if tlsManager != nil,
           cryptoManager != nil {
            return
        }

        let identity = try AndroidTVIdentityProvider.loadOrCreateIdentity()
        let publicKey = try AndroidTVIdentityProvider.publicKey(
            from: identity
        )

        let tls = TLSManager { [identity] in
            .Result(
                AndroidTVIdentityProvider.importedIdentityItems(
                    identity: identity
                )
            )
        }

        tls.secTrustClosure = { [serverKeyBox] trust in
            if let key = SecTrustCopyKey(trust) {
                serverKeyBox.set(key)
            }
        }

        let crypto = CryptoManager()
        crypto.clientPublicCertificate = { [publicKey] in
            .Result(publicKey)
        }
        crypto.serverPublicCertificate = { [serverKeyBox] in
            guard let key = serverKeyBox.get() else {
                return .Error(.noServerPublicCertificate)
            }
            return .Result(key)
        }

        tlsManager = tls
        cryptoManager = crypto
    }

    private func connectRemote() async throws {
        try prepareProtocolManagersIfNeeded()

        guard let tlsManager else {
            throw TVControlError.invalidResponse
        }

        let info = CommandNetwork.DeviceInfo(
            "iPhone",
            "Orbit",
            "1.0",
            Bundle.main.bundleIdentifier ?? "Orbit",
            Bundle.main.object(
                forInfoDictionaryKey: "CFBundleVersion"
            ) as? String ?? "1"
        )

        remoteGeneration += 1
        let generation = remoteGeneration

        if let previousManager = remoteManager {
            previousManager.stateChanged = nil
            previousManager.disconnect()
            remoteManager = nil
        }

        let manager = RemoteManager(
            tlsManager,
            info
        )
        remoteManager = manager

        let gate = AndroidTVCallbackGate<Void>()

        do {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in

                gate.install(continuation)
                gate.fail(
                    after: 10,
                    with: TVControlError.transport(
                        "Android TV did not respond in time."
                    )
                )

                manager.stateChanged = { state in
                    switch state {
                    case .paired:
                        gate.succeed(())

                    case .error(let error):
                        if AndroidTVAdapter.requiresRepair(
                            for: error
                        ) {
                            gate.fail(
                                TVControlError.permissionDenied(
                                    "Android TV no longer recognizes Orbit. Pair it again."
                                )
                            )
                        } else {
                            gate.fail(
                                TVControlError.transport(
                                    AndroidTVAdapter.userMessage(
                                        for: error
                                    )
                                )
                            )
                        }

                    default:
                        break
                    }
                }

                manager.connect(
                    device.host,
                    timeout: 8
                )
            }
        } catch {
            manager.disconnect()

            if remoteManager === manager {
                remoteManager = nil
            }

            throw error
        }

        manager.stateChanged = { [weak self, weak manager] state in
            switch state {
            case .error(let error):
                let message = AndroidTVAdapter.userMessage(
                    for: error
                )

                Task { @MainActor [weak self, weak manager] in
                    guard let self,
                          let manager,
                          self.remoteGeneration == generation,
                          self.remoteManager === manager else {
                        return
                    }

                    self.eventEmitter.yield(
                        .disconnected(
                            message: message
                        )
                    )
                }

            default:
                break
            }
        }
    }

    private func key(
        for command: RemoteCommand
    ) throws -> Key {
        switch command {
        case .power:
            return .KEYCODE_POWER
        case .up:
            return .KEYCODE_DPAD_UP
        case .down:
            return .KEYCODE_DPAD_DOWN
        case .left:
            return .KEYCODE_DPAD_LEFT
        case .right:
            return .KEYCODE_DPAD_RIGHT
        case .select:
            return .KEYCODE_DPAD_CENTER
        case .back:
            return .KEYCODE_BACK
        case .home:
            return .KEYCODE_HOME
        case .volumeUp:
            return .KEYCODE_VOLUME_UP
        case .volumeDown:
            return .KEYCODE_VOLUME_DOWN
        case .mute:
            return .KEYCODE_VOLUME_MUTE
        case .rewind:
            return .KEYCODE_MEDIA_REWIND
        case .play:
            return .KEYCODE_MEDIA_PLAY
        case .pause:
            return .KEYCODE_MEDIA_PAUSE
        case .fastForward:
            return .KEYCODE_MEDIA_FAST_FORWARD
        case .channelUp:
            return .KEYCODE_CHANNEL_UP
        case .channelDown:
            return .KEYCODE_CHANNEL_DOWN
        }
    }

    private func schedulePairingExpiry() {
        pairingExpiryTask?.cancel()

        pairingExpiryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(
                nanoseconds: 120_000_000_000
            )

            guard !Task.isCancelled,
                  let self else {
                return
            }

            self.pairingManager?.stateChanged = nil
            self.pairingManager?.disconnect()
            self.pairingManager = nil
            self.pairingExpiryTask = nil
        }
    }

    nonisolated private static func requiresRepair(
        for error: AndroidTVRemoteControlError
    ) -> Bool {
        let underlying: Error

        switch error {
        case .connectionFailed(let error),
             .connectionWaitingError(let error):
            underlying = error
        default:
            return false
        }

        guard let networkError =
                underlying as? NWError else {
            return false
        }

        if case .tls = networkError {
            return true
        }

        return false
    }

    nonisolated private static func userMessage(
        for error: AndroidTVRemoteControlError
    ) -> String {
        switch error {
        case .wrongCode:
            return "That code does not match the one on your TV. Try again."
        case .invalidCode:
            return "Enter the 6-character hexadecimal code shown on your TV."
        default:
            return "Orbit could not complete Android TV pairing. Make sure the TV is on the same Wi-Fi network and try again."
        }
    }
}

private struct AndroidTVPairingMarker: Codable {
    var pairedAt: Date = Date()
}

private final class AndroidTVServerKeyBox: @unchecked Sendable {
    private let lock = NSLock()
    private var key: SecKey?

    func set(_ key: SecKey) {
        lock.lock()
        self.key = key
        lock.unlock()
    }

    func get() -> SecKey? {
        lock.lock()
        defer { lock.unlock() }
        return key
    }
}

private final class AndroidTVCallbackGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var resolved = false

    func install(
        _ continuation: CheckedContinuation<Value, Error>
    ) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    func succeed(_ value: Value) {
        finish(.success(value))
    }

    func fail(_ error: Error) {
        finish(.failure(error))
    }

    func fail(
        after timeout: TimeInterval,
        with error: Error
    ) {
        let task = Task { [weak self] in
            try? await Task.sleep(
                nanoseconds: UInt64(
                    max(0, timeout) * 1_000_000_000
                )
            )

            guard !Task.isCancelled else {
                return
            }

            self?.fail(error)
        }

        lock.lock()

        if resolved {
            lock.unlock()
            task.cancel()
            return
        }

        timeoutTask?.cancel()
        timeoutTask = task
        lock.unlock()
    }

    private func finish(
        _ result: Swift.Result<Value, Error>
    ) {
        lock.lock()

        guard !resolved else {
            lock.unlock()
            return
        }

        resolved = true
        let continuation = self.continuation
        self.continuation = nil
        let timeoutTask = self.timeoutTask
        self.timeoutTask = nil
        lock.unlock()

        timeoutTask?.cancel()

        switch result {
        case .success(let value):
            continuation?.resume(returning: value)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
    }
}

