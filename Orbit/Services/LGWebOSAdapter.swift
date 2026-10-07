import Foundation
import Security

@MainActor
final class LGWebOSAdapter: NSObject, TVControlling {
    private(set) var device: TVDevice

    private static let securePort = 3001

    private let trustDelegate: LGLocalTrustDelegate
    private let eventEmitter = TVAdapterEventEmitter()

    private var transport: JSONWebSocketTransport?
    private var pointerSession: URLSession?
    private var pointerTask: URLSessionWebSocketTask?
    private var pointerReaderTask: Task<Void, Never>?
    private var pointerPingTask: Task<Void, Never>?
    private var requestCounter = 0

    var events: AsyncStream<TVAdapterEvent> {
        eventEmitter.stream
    }

    init(device: TVDevice) {
        self.device = device
        self.trustDelegate = LGLocalTrustDelegate(
            host: device.host
        )
    }

    func identify() async throws -> TVDevice {
        guard let url = URL(
            string:
                "wss://\(device.host):\(Self.securePort)"
        ) else {
            throw TVControlError.invalidResponse
        }

        let configuration =
            URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 8
        configuration.waitsForConnectivity = false

        let probe = JSONWebSocketTransport(
            url: url,
            configuration: configuration,
            delegate: trustDelegate
        )
        probe.start()
        defer { probe.disconnect() }

        try await probe.sendJSONObject([
            "id": "orbit_hello",
            "type": "hello",
            "payload": [:]
        ])

        let data = try await probe.nextEvent(
            timeout: 5
        )
        let root = try decode(data)

        guard root["type"] as? String == "hello",
              let payload =
                root["payload"] as? [String: Any],
              let rawUUID =
                payload["deviceUUID"] as? String else {
            throw TVControlError.invalidResponse
        }

        let uuid = rawUUID
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .lowercased()

        guard !uuid.isEmpty else {
            throw TVControlError.invalidResponse
        }

        let resolvedID = "lg-\(uuid)"
        let manualID = "lg-\(device.host)"
        var aliases = device.discoveryAliases

        if device.id != manualID,
           device.id != resolvedID {
            aliases.insert(device.id)
        }

        return TVDevice(
            id: resolvedID,
            name: device.name,
            platform: .lgWebOS,
            host: device.host,
            port: Self.securePort,
            roomName: device.roomName,
            discoveryIDs:
                aliases.isEmpty ? nil : aliases,
            capabilities:
                device.capabilities
        )
    }

    func connect() async throws -> TVConnectionInfo {
        await disconnect()

        let previousID = device.id
        let identified = try await identify()
        device = identified

        if previousID != identified.id,
           let credential =
                try? PairingCredentialStore.load(
                    LGCredential.self,
                    platform: .lgWebOS,
                    deviceID: previousID
                ) {
            try? PairingCredentialStore.save(
                credential,
                platform: .lgWebOS,
                deviceID: identified.id
            )
            PairingCredentialStore.remove(
                platform: .lgWebOS,
                deviceID: previousID
            )
        }

        try await connect(
            using: "wss",
            port: Self.securePort
        )

        await refreshDeviceMetadataIfAvailable()

        let capabilities: Set<TVCapability> = [
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

        device.capabilities = capabilities

        try await connectPointerSocket()

        return TVConnectionInfo(
            state: .connected,
            capabilities: capabilities,
            pairingRequirement: .none
        )
    }

    func disconnect() async {
        pointerPingTask?.cancel()
        pointerPingTask = nil

        pointerReaderTask?.cancel()
        pointerReaderTask = nil

        pointerTask?.cancel(
            with: .normalClosure,
            reason: nil
        )
        pointerTask = nil

        pointerSession?.invalidateAndCancel()
        pointerSession = nil

        transport?.disconnect()
        transport = nil
    }

    func send(_ command: RemoteCommand) async throws {
        switch command {
        case .power:
            _ = try await request(
                uri: "ssap://system/turnOff"
            )

        default:
            try await sendPointerButton(
                try pointerButton(
                    for: command
                )
            )
        }
    }

    func send(text: String) async throws {
        guard !text.isEmpty else { return }

        _ = try await request(
            uri:
                "ssap://com.webos.service.ime/insertText",
            payload: [
                "text": text,
                "replace": 0
            ]
        )
    }

    func apps() async throws -> [TVApp] {
        let payload = try await request(
            uri:
                "ssap://com.webos.applicationManager/listLaunchPoints"
        )

        guard let launchPoints =
            payload["launchPoints"] as? [[String: Any]] else {
            return []
        }

        return launchPoints.compactMap { item in
            guard let id = item["id"] as? String else {
                return nil
            }

            return TVApp(
                id: id,
                name:
                    (item["title"] as? String) ??
                    id
            )
        }
        .sorted {
            $0.name.localizedCaseInsensitiveCompare(
                $1.name
            ) == .orderedAscending
        }
    }

    func inputs() async throws -> [TVInput] {
        let payload = try await request(
            uri:
                "ssap://tv/getExternalInputList"
        )

        guard let devices =
            payload["devices"] as? [[String: Any]] else {
            return []
        }

        return devices.compactMap { item in
            guard let id = item["id"] as? String else {
                return nil
            }

            return TVInput(
                id: id,
                name:
                    (item["label"] as? String) ??
                    id
            )
        }
    }

    func launch(app: TVApp) async throws {
        _ = try await request(
            uri: "ssap://system.launcher/launch",
            payload: ["id": app.id]
        )
    }

    func select(input: TVInput) async throws {
        _ = try await request(
            uri: "ssap://tv/switchInput",
            payload: ["inputId": input.id]
        )
    }

    private func connect(
        using scheme: String,
        port: Int
    ) async throws {
        guard let url = URL(
            string:
                "\(scheme)://\(device.host):\(port)"
        ) else {
            throw TVControlError.invalidResponse
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 86_400
        configuration.waitsForConnectivity = false

        let transport = JSONWebSocketTransport(
            url: url,
            configuration: configuration,
            delegate:
                scheme == "wss"
                ? trustDelegate
                : nil
        )

        self.transport = transport

        transport.onUnexpectedClose = {
            [weak eventEmitter] error in

            eventEmitter?.yield(
                .disconnected(
                    message: error?.localizedDescription
                )
            )
        }

        transport.start()

        let credential = try? PairingCredentialStore.load(
            LGCredential.self,
            platform: .lgWebOS,
            deviceID: device.id
        )
        var usedStoredClientKey =
            credential?.clientKey != nil
        var retriedWithoutStoredKey = false

        try await transport.sendJSONObject(
            registrationMessage(
                clientKey: credential?.clientKey
            )
        )

        var sawPrompt = false

        for _ in 0..<8 {
            let data: Data

            do {
                data = try await transport.nextEvent(
                    timeout: 60
                )
            } catch {
                if sawPrompt {
                    throw TVControlError.permissionDenied(
                        "Check your LG TV and accept the Orbit pairing prompt."
                    )
                }

                throw error
            }

            let root = try decode(data)

            if root["type"] as? String == "response",
               let payload =
                   root["payload"] as? [String: Any],
               let pairingType =
                   payload["pairingType"] as? String {
                sawPrompt =
                    pairingType.uppercased() ==
                    "PROMPT"
                continue
            }

            if root["type"] as? String == "registered",
               let payload =
                   root["payload"] as? [String: Any],
               let clientKey =
                   payload["client-key"] as? String,
               !clientKey.isEmpty {
                try? PairingCredentialStore.save(
                    LGCredential(
                        clientKey: clientKey
                    ),
                    platform: .lgWebOS,
                    deviceID: device.id
                )

                let connectedDeviceID =
                    device.id

                transport.onEvent = {
                    [weak eventEmitter] data in

                    guard let root = try? JSONSerialization.jsonObject(
                        with: data
                    ) as? [String: Any],
                    root["type"] as? String == "error" else {
                        return
                    }

                    let message =
                        (root["error"] as? String) ??
                        "LG TV rejected a request."
                    let lowered =
                        message.lowercased()

                    guard lowered.contains("401") ||
                            lowered.contains("403") ||
                            lowered.contains(
                                "unauthorized"
                            ) else {
                        return
                    }

                    PairingCredentialStore.remove(
                        platform: .lgWebOS,
                        deviceID: connectedDeviceID
                    )

                    eventEmitter?.yield(
                        .pairingRevoked(
                            message:
                                "LG TV revoked Orbit’s remote access. Pair the TV again."
                        )
                    )
                }

                return
            }

            if root["type"] as? String == "error" {
                let message =
                    (root["error"] as? String) ??
                    "Pairing failed."
                let lowered = message.lowercased()
                let authorizationFailure =
                    lowered.contains("401") ||
                    lowered.contains("403") ||
                    lowered.contains("unauthorized")

                if authorizationFailure,
                   usedStoredClientKey,
                   !retriedWithoutStoredKey {
                    PairingCredentialStore.remove(
                        platform: .lgWebOS,
                        deviceID: device.id
                    )
                    usedStoredClientKey = false
                    retriedWithoutStoredKey = true
                    sawPrompt = false

                    try await transport.sendJSONObject(
                        registrationMessage(
                            clientKey: nil
                        )
                    )
                    continue
                }

                if authorizationFailure ||
                    sawPrompt {
                    throw TVControlError.permissionDenied(
                        "LG TV denied Orbit. Connect again and accept the pairing prompt on your TV."
                    )
                }

                throw TVControlError.invalidResponse
            }
        }

        throw TVControlError.permissionDenied(
            "Check your LG TV and accept the Orbit pairing prompt."
        )
    }

    private func connectPointerSocket() async throws {
        let payload = try await request(
            uri:
                "ssap://com.webos.service.networkinput/getPointerInputSocket"
        )

        guard let socketPath =
            payload["socketPath"] as? String,
              let url = URL(
                  string: socketPath
              ) else {
            throw TVControlError.invalidResponse
        }

        let configuration =
            URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 0
        configuration.waitsForConnectivity = false

        let session = URLSession(
            configuration: configuration,
            delegate:
                url.scheme == "wss"
                ? trustDelegate
                : nil,
            delegateQueue: nil
        )

        pointerSession = session

        let task = session.webSocketTask(
            with: url
        )
        pointerTask = task
        task.resume()

        pointerReaderTask = Task {
            @MainActor [weak self, weak task] in

            guard let task else {
                return
            }

            while !Task.isCancelled {
                do {
                    _ = try await task.receive()
                } catch is CancellationError {
                    return
                } catch {
                    guard let self,
                          self.pointerTask === task else {
                        return
                    }

                    self.pointerPingTask?.cancel()
                    self.pointerPingTask = nil
                    self.eventEmitter.yield(
                        .disconnected(
                            message:
                                "LG TV’s navigation connection was interrupted."
                        )
                    )
                    return
                }
            }
        }

        pointerPingTask = Task {
            @MainActor [weak self, weak task] in

            guard let task else {
                return
            }

            while !Task.isCancelled {
                do {
                    try await Task.sleep(
                        nanoseconds:
                            20_000_000_000
                    )
                    try Task.checkCancellation()
                    try await self?.sendPing(
                        on: task
                    )
                } catch is CancellationError {
                    return
                } catch {
                    guard let self,
                          self.pointerTask === task else {
                        return
                    }

                    self.pointerReaderTask?.cancel()
                    self.pointerReaderTask = nil
                    self.eventEmitter.yield(
                        .disconnected(
                            message:
                                "LG TV’s navigation connection stopped responding."
                        )
                    )
                    return
                }
            }
        }
    }

    private func sendPing(
        on task: URLSessionWebSocketTask
    ) async throws {
        try await withCheckedThrowingContinuation {
            (
                continuation:
                    CheckedContinuation<Void, Error>
            ) in

            task.sendPing { error in
                if let error {
                    continuation.resume(
                        throwing: error
                    )
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func refreshDeviceMetadataIfAvailable() async {
        guard let payload = try? await request(
            uri:
                "ssap://com.webos.service.update/getCurrentSWInformation"
        ) else {
            return
        }

        if let modelName =
                payload["model_name"] as? String,
           device.name == "LG TV",
           !modelName.isEmpty {
            device.name = "LG \(modelName)"
        }
    }

    private func request(
        uri: String,
        payload: [String: Any]? = nil
    ) async throws -> [String: Any] {
        guard let transport else {
            throw TVControlError.unreachable
        }

        requestCounter += 1
        let id = "orbit_\(requestCounter)"

        var object: [String: Any] = [
            "type": "request",
            "id": id,
            "uri": uri
        ]

        if let payload {
            object["payload"] = payload
        }

        let data = try await transport.requestJSONObject(
            object,
            id: id,
            timeout: 8
        )
        let response = try decode(data)

        if response["type"] as? String == "error" {
            let message =
                response["error"] as? String ??
                "LG TV rejected the request."

            if message.contains("401") ||
                message.contains("403") {
                throw TVControlError.permissionDenied(
                    message
                )
            }

            throw TVControlError.rejected(
                status: nil,
                message: message
            )
        }

        return (
            response["payload"] as? [String: Any]
        ) ?? [:]
    }

    private func sendPointerButton(
        _ name: String
    ) async throws {
        guard let task = pointerTask else {
            throw TVControlError.unreachable
        }

        let message =
            "type:button\nname:\(name)\n\n"

        do {
            try await task.send(
                .string(message)
            )
        } catch {
            if pointerTask === task {
                eventEmitter.yield(
                    .disconnected(
                        message:
                            "LG TV’s navigation connection was interrupted."
                    )
                )
            }

            throw TVControlError.unreachable
        }
    }

    private func pointerButton(
        for command: RemoteCommand
    ) throws -> String {
        switch command {
        case .power:
            throw TVControlError.unsupported
        case .up:
            return "UP"
        case .down:
            return "DOWN"
        case .left:
            return "LEFT"
        case .right:
            return "RIGHT"
        case .select:
            return "ENTER"
        case .back:
            return "BACK"
        case .home:
            return "HOME"
        case .volumeUp:
            return "VOLUMEUP"
        case .volumeDown:
            return "VOLUMEDOWN"
        case .mute:
            return "MUTE"
        case .rewind:
            return "REWIND"
        case .play:
            return "PLAY"
        case .pause:
            return "PAUSE"
        case .fastForward:
            return "FASTFORWARD"
        case .channelUp:
            return "CHANNELUP"
        case .channelDown:
            return "CHANNELDOWN"
        }
    }

    private func registrationMessage(
        clientKey: String?
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "forcePairing": false,
            "pairingType": "PROMPT",
            "manifest": [
                "manifestVersion": 1,
                "permissions": [
                    "LAUNCH",
                    "LAUNCH_WEBAPP",
                    "APP_TO_APP",
                    "CLOSE",
                    "CONTROL_AUDIO",
                    "CONTROL_DISPLAY",
                    "CONTROL_INPUT_JOYSTICK",
                    "CONTROL_INPUT_MEDIA_PLAYBACK",
                    "CONTROL_INPUT_TV",
                    "CONTROL_POWER",
                    "READ_APP_STATUS",
                    "READ_CURRENT_CHANNEL",
                    "READ_INPUT_DEVICE_LIST",
                    "READ_NETWORK_STATE",
                    "READ_RUNNING_APPS",
                    "READ_TV_CHANNEL_LIST",
                    "READ_POWER_STATE",
                    "CONTROL_INPUT_TEXT",
                    "CONTROL_MOUSE_AND_KEYBOARD",
                    "READ_INSTALLED_APPS"
                ]
            ]
        ]

        if let clientKey,
           !clientKey.isEmpty {
            payload["client-key"] = clientKey
        }

        return [
            "type": "register",
            "id": "register_0",
            "payload": payload
        ]
    }

    private func decode(
        _ data: Data
    ) throws -> [String: Any] {
        guard let root = try JSONSerialization.jsonObject(
            with: data
        ) as? [String: Any] else {
            throw TVControlError.invalidResponse
        }

        return root
    }
}

private struct LGCredential: Codable {
    let clientKey: String
}

private final class LGLocalTrustDelegate:
    NSObject,
    URLSessionDelegate,
    @unchecked Sendable {

    private let host: String

    init(host: String) {
        self.host = host
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler:
            @escaping (
                URLSession.AuthChallengeDisposition,
                URLCredential?
            ) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod ==
                NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host == host,
              isPrivateIPv4(host),
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(
                .performDefaultHandling,
                nil
            )
            return
        }

        completionHandler(
            .useCredential,
            URLCredential(trust: trust)
        )
    }

    private func isPrivateIPv4(
        _ value: String
    ) -> Bool {
        let parts = value
            .split(separator: ".")
            .compactMap { Int($0) }

        guard parts.count == 4 else {
            return false
        }

        if parts[0] == 10 { return true }
        if parts[0] == 172 &&
            (16...31).contains(parts[1]) {
            return true
        }
        if parts[0] == 192 &&
            parts[1] == 168 {
            return true
        }
        if parts[0] == 169 &&
            parts[1] == 254 {
            return true
        }

        return false
    }
}
