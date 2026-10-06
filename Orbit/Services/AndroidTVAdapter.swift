import Foundation
import Security
@preconcurrency import AndroidTVRemoteControl

@MainActor
final class AndroidTVAdapter: TVControlling {
    private(set) var device: TVDevice

    private let serverKeyBox = AndroidTVServerKeyBox()

    private var tlsManager: TLSManager?
    private var cryptoManager: CryptoManager?
    private var pairingManager: PairingManager?
    private var remoteManager: RemoteManager?

    init(device: TVDevice) {
        self.device = device
    }

    func connect() async throws -> TVConnectionInfo {
        try prepareProtocolManagersIfNeeded()

        if hasPairingMarker {
            do {
                try await connectRemote()
                return connectedInfo()
            } catch {
                PairingCredentialStore.remove(
                    platform: .androidTV,
                    deviceID: device.id
                )
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
        pairingManager?.disconnect()
        pairingManager = nil

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

        return try await withCheckedThrowingContinuation { continuation in
            gate.install(continuation)

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
                            AndroidTVAdapter.userMessage(for: error)
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

        let gate = AndroidTVCallbackGate<Void>()

        try await withCheckedThrowingContinuation { continuation in
            gate.install(continuation)

            manager.stateChanged = { state in
                switch state {
                case .successPaired:
                    gate.succeed(())

                case .error(let error):
                    gate.fail(
                        TVControlError.permissionDenied(
                            AndroidTVAdapter.userMessage(for: error)
                        )
                    )

                default:
                    break
                }
            }

            manager.sendSecret(code)
        }

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

        let manager = RemoteManager(
            tlsManager,
            info
        )
        remoteManager = manager

        let gate = AndroidTVCallbackGate<Void>()

        try await withCheckedThrowingContinuation { continuation in
            gate.install(continuation)

            manager.stateChanged = { state in
                switch state {
                case .paired:
                    gate.succeed(())

                case .error(let error):
                    gate.fail(
                        TVControlError.unreachableWith(
                            AndroidTVAdapter.userMessage(for: error)
                        )
                    )

                default:
                    break
                }
            }

            manager.connect(
                device.host,
                timeout: 8
            )
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

private final class AndroidTVCallbackGate<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
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
        lock.unlock()

        switch result {
        case .success(let value):
            continuation?.resume(returning: value)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
    }
}

private extension TVControlError {
    static func unreachableWith(
        _ message: String
    ) -> TVControlError {
        .permissionDenied(message)
    }
}
