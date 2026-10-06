import Foundation
import Security

@MainActor
final class LGWebOSAdapter: NSObject, TVControlling {
    private(set) var device: TVDevice

    private static let securePort = 3001
    private static let plainPort = 3000

    private let trustDelegate: LGLocalTrustDelegate
    private let webSocketSession: URLSession

    private var mainTask: URLSessionWebSocketTask?
    private var pointerTask: URLSessionWebSocketTask?
    private var requestCounter = 0

    init(device: TVDevice) {
        self.device = device

        let delegate = LGLocalTrustDelegate(host: device.host)
        self.trustDelegate = delegate

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5.0
        configuration.timeoutIntervalForResource = 45.0
        configuration.waitsForConnectivity = false

        self.webSocketSession = URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: nil
        )
    }

    func connect() async throws -> TVConnectionInfo {
        await disconnect()

        do {
            try await connect(using: "wss", port: Self.securePort)
        } catch let error as TVControlError {
            if case .permissionDenied = error {
                throw error
            }

            await disconnect()
            try await connect(using: "ws", port: Self.plainPort)
        } catch {
            await disconnect()
            try await connect(using: "ws", port: Self.plainPort)
        }

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
        pointerTask?.cancel(with: .normalClosure, reason: nil)
        pointerTask = nil

        mainTask?.cancel(with: .normalClosure, reason: nil)
        mainTask = nil
    }

    func send(_ command: RemoteCommand) async throws {
        switch command {
        case .power:
            _ = try await request(uri: "ssap://system/turnOff")
        default:
            try await sendPointerButton(try pointerButton(for: command))
        }
    }

    func send(text: String) async throws {
        guard !text.isEmpty else { return }

        _ = try await request(
            uri: "ssap://com.webos.service.ime/insertText",
            payload: [
                "text": text,
                "replace": 0
            ]
        )
    }

    func apps() async throws -> [TVApp] {
        let payload = try await request(
            uri: "ssap://com.webos.applicationManager/listLaunchPoints"
        )

        guard let launchPoints = payload["launchPoints"] as? [[String: Any]] else {
            return []
        }

        return launchPoints.compactMap { item in
            guard let id = item["id"] as? String else { return nil }
            let title = (item["title"] as? String) ?? id
            return TVApp(id: id, name: title)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func inputs() async throws -> [TVInput] {
        let payload = try await request(uri: "ssap://tv/getExternalInputList")

        guard let devices = payload["devices"] as? [[String: Any]] else {
            return []
        }

        return devices.compactMap { item in
            guard let id = item["id"] as? String else { return nil }
            let label = (item["label"] as? String) ?? id
            return TVInput(id: id, name: label)
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

    private func connect(using scheme: String, port: Int) async throws {
        guard let url = URL(string: "\(scheme)://\(device.host):\(port)") else {
            throw TVControlError.invalidResponse
        }

        let task = webSocketSession.webSocketTask(with: url)
        mainTask = task
        task.resume()

        let credential = try? PairingCredentialStore.load(
            LGCredential.self,
            platform: .lgWebOS,
            deviceID: device.id
        )

        let registration = registrationMessage(clientKey: credential?.clientKey)
        try await sendJSON(registration, on: task)

        var sawPrompt = false

        for _ in 0..<4 {
            let message: URLSessionWebSocketTask.Message

            do {
                message = try await task.receive()
            } catch {
                throw TVControlError.unreachable
            }

            let root = try decode(message)

            if root["type"] as? String == "response",
               let payload = root["payload"] as? [String: Any],
               let pairingType = payload["pairingType"] as? String {
                sawPrompt = pairingType.uppercased() == "PROMPT"
                continue
            }

            if root["type"] as? String == "registered",
               let payload = root["payload"] as? [String: Any],
               let clientKey = payload["client-key"] as? String,
               !clientKey.isEmpty {
                try? PairingCredentialStore.save(
                    LGCredential(clientKey: clientKey),
                    platform: .lgWebOS,
                    deviceID: device.id
                )
                return
            }

            if root["type"] as? String == "error" {
                let message = (root["error"] as? String) ?? "Pairing failed."

                if message.contains("403") || sawPrompt {
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
            uri: "ssap://com.webos.service.networkinput/getPointerInputSocket"
        )

        guard let socketPath = payload["socketPath"] as? String,
              let url = URL(string: socketPath) else {
            throw TVControlError.invalidResponse
        }

        let task = webSocketSession.webSocketTask(with: url)
        pointerTask = task
        task.resume()
    }

    private func request(
        uri: String,
        payload: [String: Any]? = nil
    ) async throws -> [String: Any] {
        guard let task = mainTask else {
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

        try await sendJSON(object, on: task)

        for _ in 0..<8 {
            let message: URLSessionWebSocketTask.Message

            do {
                message = try await task.receive()
            } catch {
                throw TVControlError.unreachable
            }

            let response = try decode(message)

            guard response["id"] as? String == id else {
                continue
            }

            if response["type"] as? String == "error" {
                let message = response["error"] as? String ?? "LG TV rejected the request."

                if message.contains("401") || message.contains("403") {
                    throw TVControlError.permissionDenied(message)
                }

                throw TVControlError.invalidResponse
            }

            return (response["payload"] as? [String: Any]) ?? [:]
        }

        throw TVControlError.invalidResponse
    }

    private func sendPointerButton(_ name: String) async throws {
        guard let task = pointerTask else {
            throw TVControlError.unreachable
        }

        let message = "type:button\nname:\(name)\n\n"

        do {
            try await task.send(.string(message))
        } catch {
            throw TVControlError.unreachable
        }
    }

    private func pointerButton(for command: RemoteCommand) throws -> String {
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

    private func registrationMessage(clientKey: String?) -> [String: Any] {
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

        if let clientKey, !clientKey.isEmpty {
            payload["client-key"] = clientKey
        }

        return [
            "type": "register",
            "id": "register_0",
            "payload": payload
        ]
    }

    private func sendJSON(
        _ object: [String: Any],
        on task: URLSessionWebSocketTask
    ) async throws {
        let data = try JSONSerialization.data(withJSONObject: object)

        guard let string = String(data: data, encoding: .utf8) else {
            throw TVControlError.invalidResponse
        }

        do {
            try await task.send(.string(string))
        } catch {
            throw TVControlError.unreachable
        }
    }

    private func decode(
        _ message: URLSessionWebSocketTask.Message
    ) throws -> [String: Any] {
        let data: Data

        switch message {
        case .string(let string):
            guard let encoded = string.data(using: .utf8) else {
                throw TVControlError.invalidResponse
            }
            data = encoded
        case .data(let payload):
            data = payload
        @unknown default:
            throw TVControlError.invalidResponse
        }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TVControlError.invalidResponse
        }

        return root
    }
}

private struct LGCredential: Codable {
    let clientKey: String
}

private final class LGLocalTrustDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let host: String

    init(host: String) {
        self.host = host
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host == host,
              isPrivateIPv4(host),
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    private func isPrivateIPv4(_ value: String) -> Bool {
        let parts = value.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }

        if parts[0] == 10 { return true }
        if parts[0] == 172 && (16...31).contains(parts[1]) { return true }
        if parts[0] == 192 && parts[1] == 168 { return true }
        if parts[0] == 169 && parts[1] == 254 { return true }
        if parts[0] == 100 && (64...127).contains(parts[1]) { return true }

        return false
    }
}
