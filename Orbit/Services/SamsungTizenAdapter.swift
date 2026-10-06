import Foundation
import Security

@MainActor
final class SamsungTizenAdapter: NSObject, TVControlling {
    private(set) var device: TVDevice

    private static let appName = "Orbit"
    private static let restPort = 8001
    private static let securePort = 8002

    private let restSession: URLSession
    private let trustDelegate: SamsungLocalTrustDelegate
    private let webSocketSession: URLSession

    private var webSocketTask: URLSessionWebSocketTask?
    private var metadata: SamsungTVMetadata?

    init(device: TVDevice) {
        self.device = device

        let restConfiguration = URLSessionConfiguration.ephemeral
        restConfiguration.timeoutIntervalForRequest = 2.5
        restConfiguration.timeoutIntervalForResource = 4.0
        restConfiguration.waitsForConnectivity = false
        self.restSession = URLSession(configuration: restConfiguration)

        let trustDelegate = SamsungLocalTrustDelegate(host: device.host)
        self.trustDelegate = trustDelegate

        let webSocketConfiguration = URLSessionConfiguration.ephemeral
        webSocketConfiguration.timeoutIntervalForRequest = 5.0
        webSocketConfiguration.timeoutIntervalForResource = 45.0
        webSocketConfiguration.waitsForConnectivity = false
        self.webSocketSession = URLSession(
            configuration: webSocketConfiguration,
            delegate: trustDelegate,
            delegateQueue: nil
        )
    }

    func connect() async throws -> TVConnectionInfo {
        await disconnect()

        let metadata = try await fetchMetadata()
        self.metadata = metadata
        device = resolvedDevice(from: metadata)

        let storedCredential = try? PairingCredentialStore.load(
            SamsungCredential.self,
            platform: .samsung,
            deviceID: device.id
        )

        let task = try makeWebSocketTask(token: storedCredential?.token)
        webSocketTask = task
        task.resume()

        let firstMessage = try await task.receive()
        let envelope = try parseEnvelope(firstMessage)

        guard envelope.event == "ms.channel.connect" else {
            task.cancel(with: .goingAway, reason: nil)
            webSocketTask = nil

            if envelope.event == "ms.channel.unauthorized" {
                throw TVControlError.permissionDenied(
                    "Samsung TV denied Orbit. Remove Orbit from the TV’s device connection list, then connect again and choose Allow."
                )
            }

            throw TVControlError.permissionDenied(
                "Check your Samsung TV and allow Orbit to connect."
            )
        }

        if let token = envelope.token, !token.isEmpty {
            try? PairingCredentialStore.save(
                SamsungCredential(token: token),
                platform: .samsung,
                deviceID: device.id
            )
        }

        return TVConnectionInfo(
            state: metadata.isPoweredOff ? .off : .connected,
            capabilities: device.capabilities,
            pairingRequirement: .none
        )
    }

    func disconnect() async {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
    }

    func send(_ command: RemoteCommand) async throws {
        try await sendKey(try key(for: command), command: "Click")
    }

    func beginPress(_ command: RemoteCommand) async throws {
        try await sendKey(try key(for: command), command: "Press")
    }

    func endPress(_ command: RemoteCommand) async throws {
        try await sendKey(try key(for: command), command: "Release")
    }

    func send(text: String) async throws {
        guard !text.isEmpty else { return }

        let encoded = Data(text.utf8).base64EncodedString()

        try await sendJSON([
            "method": "ms.remote.control",
            "params": [
                "Cmd": encoded,
                "DataOfCmd": "base64",
                "TypeOfRemote": "SendInputString"
            ]
        ])

        try await sendJSON([
            "method": "ms.remote.control",
            "params": [
                "TypeOfRemote": "SendInputEnd"
            ]
        ])
    }

    func apps() async throws -> [TVApp] {
        []
    }

    func inputs() async throws -> [TVInput] {
        [
            TVInput(id: "KEY_SOURCE", name: "Source"),
            TVInput(id: "KEY_HDMI1", name: "HDMI 1"),
            TVInput(id: "KEY_HDMI2", name: "HDMI 2"),
            TVInput(id: "KEY_HDMI3", name: "HDMI 3"),
            TVInput(id: "KEY_HDMI4", name: "HDMI 4")
        ]
    }

    func launch(app: TVApp) async throws {
        throw TVControlError.unsupported
    }

    func select(input: TVInput) async throws {
        try await sendKey(input.id, command: "Click")
    }

    private func fetchMetadata() async throws -> SamsungTVMetadata {
        guard let url = URL(string: "http://\(device.host):\(Self.restPort)/api/v2/") else {
            throw TVControlError.invalidResponse
        }

        do {
            let (data, response) = try await restSession.data(from: url)

            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                throw TVControlError.unreachable
            }

            return try SamsungTVMetadata.parse(data: data)
        } catch let error as TVControlError {
            throw error
        } catch {
            throw TVControlError.unreachable
        }
    }

    private func resolvedDevice(from metadata: SamsungTVMetadata) -> TVDevice {
        let stableID = metadata.stableID ?? device.id

        return TVDevice(
            id: "samsung-\(stableID)",
            name: metadata.name ?? "Samsung TV",
            platform: .samsung,
            host: device.host,
            port: Self.securePort,
            roomName: device.roomName,
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
    }

    private func makeWebSocketTask(token: String?) throws -> URLSessionWebSocketTask {
        var components = URLComponents()
        components.scheme = "wss"
        components.host = device.host
        components.port = device.port ?? Self.securePort
        components.path = "/api/v2/channels/samsung.remote.control"

        var queryItems = [
            URLQueryItem(
                name: "name",
                value: Data(Self.appName.utf8).base64EncodedString()
            )
        ]

        if let token, !token.isEmpty {
            queryItems.append(URLQueryItem(name: "token", value: token))
        }

        components.queryItems = queryItems

        guard let url = components.url else {
            throw TVControlError.invalidResponse
        }

        return webSocketSession.webSocketTask(with: url)
    }

    private func sendKey(_ key: String, command: String) async throws {
        try await sendJSON([
            "method": "ms.remote.control",
            "params": [
                "Cmd": command,
                "DataOfCmd": key,
                "Option": "false",
                "TypeOfRemote": "SendRemoteKey"
            ]
        ])
    }

    private func sendJSON(_ object: [String: Any]) async throws {
        guard let task = webSocketTask else {
            throw TVControlError.unreachable
        }

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

    private func parseEnvelope(
        _ message: URLSessionWebSocketTask.Message
    ) throws -> SamsungWebSocketEnvelope {
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

        let event = root["event"] as? String
        let eventData = root["data"] as? [String: Any]
        let token = eventData?["token"] as? String

        return SamsungWebSocketEnvelope(event: event, token: token)
    }

    private func key(for command: RemoteCommand) throws -> String {
        switch command {
        case .power:
            return "KEY_POWER"
        case .up:
            return "KEY_UP"
        case .down:
            return "KEY_DOWN"
        case .left:
            return "KEY_LEFT"
        case .right:
            return "KEY_RIGHT"
        case .select:
            return "KEY_ENTER"
        case .back:
            return "KEY_RETURN"
        case .home:
            return "KEY_HOME"
        case .volumeUp:
            return "KEY_VOLUP"
        case .volumeDown:
            return "KEY_VOLDOWN"
        case .mute:
            return "KEY_MUTE"
        case .rewind:
            return "KEY_REWIND"
        case .play:
            return "KEY_PLAY"
        case .pause:
            return "KEY_PAUSE"
        case .fastForward:
            return "KEY_FF"
        case .channelUp:
            return "KEY_CHUP"
        case .channelDown:
            return "KEY_CHDOWN"
        }
    }
}

private struct SamsungCredential: Codable {
    let token: String
}

private struct SamsungWebSocketEnvelope {
    let event: String?
    let token: String?
}

private struct SamsungTVMetadata {
    let stableID: String?
    let name: String?
    let os: String?
    let powerState: String?

    var isPoweredOff: Bool {
        guard let powerState else { return false }
        return powerState.lowercased() == "off"
    }

    static func parse(data: Data) throws -> SamsungTVMetadata {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let device = root["device"] as? [String: Any] else {
            throw TVControlError.invalidResponse
        }

        let os = device["OS"] as? String
        guard os?.lowercased().contains("tizen") == true else {
            throw TVControlError.invalidResponse
        }

        let rawName = device["name"] as? String
        let name = rawName?.removingPercentEncoding ?? rawName

        let stableID =
            (device["id"] as? String) ??
            (device["duid"] as? String) ??
            (device["udn"] as? String)

        return SamsungTVMetadata(
            stableID: stableID,
            name: name,
            os: os,
            powerState: device["PowerState"] as? String
        )
    }
}

private final class SamsungLocalTrustDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
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
