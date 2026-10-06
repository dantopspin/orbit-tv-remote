import Foundation
import Security

@MainActor
final class FireTVAdapter: NSObject, TVControlling {
    private(set) var device: TVDevice

    private static let apiKey = "0987654321"
    private static let lightningPort = 8080
    private static let wakePort = 8009

    private let trustDelegate: FireTVLocalTrustDelegate
    private let session: URLSession

    private var credential: FireTVCredential?
    private var pinDisplayed = false

    init(device: TVDevice) {
        self.device = device

        let delegate = FireTVLocalTrustDelegate(
            host: device.host
        )
        self.trustDelegate = delegate

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3.0
        configuration.timeoutIntervalForResource = 5.0
        configuration.waitsForConnectivity = false

        self.session = URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: nil
        )

        super.init()

        credential = try? PairingCredentialStore.load(
            FireTVCredential.self,
            platform: .fireTV,
            deviceID: device.id
        )
    }

    func connect() async throws -> TVConnectionInfo {
        if let credential {
            switch await validate(
                token: credential.token
            ) {
            case .valid:
                return connectedInfo()

            case .unauthorized:
                PairingCredentialStore.remove(
                    platform: .fireTV,
                    deviceID: device.id
                )
                self.credential = nil

            case .unreachable:
                _ = try? await wake()

                for _ in 0..<5 {
                    try? await Task.sleep(
                        nanoseconds: 500_000_000
                    )

                    switch await validate(
                        token: credential.token
                    ) {
                    case .valid:
                        return connectedInfo()

                    case .unauthorized:
                        PairingCredentialStore.remove(
                            platform: .fireTV,
                            deviceID: device.id
                        )
                        self.credential = nil
                        break

                    case .unreachable:
                        continue
                    }

                    if self.credential == nil {
                        break
                    }
                }
            }
        }

        let requirement = try await pairingRequirement()

        return TVConnectionInfo(
            state: .connecting,
            capabilities: capabilities,
            pairingRequirement: requirement
        )
    }

    func pairingRequirement() async throws -> TVPairingRequirement {
        if !pinDisplayed {
            _ = try? await wake()
            try await displayPin()
            pinDisplayed = true
        }

        return .pin(
            length: 4,
            message: "Enter the 4-digit code shown on your Fire TV."
        )
    }

    func pair(
        using response: TVPairingResponse
    ) async throws {
        guard case .pin(let rawPin) = response else {
            throw TVControlError.permissionDenied(
                "Enter the 4-digit code shown on your Fire TV."
            )
        }

        let pin = rawPin.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard pin.count == 4,
              pin.allSatisfy(\.isNumber) else {
            throw TVControlError.permissionDenied(
                "The Fire TV pairing code contains 4 digits."
            )
        }

        let body = try JSONSerialization.data(
            withJSONObject: ["pin": pin]
        )

        let result = try await request(
            path: "/v1/FireTV/pin/verify",
            method: "POST",
            body: body,
            token: nil
        )

        guard (200..<300).contains(
            result.response.statusCode
        ) else {
            throw pairingError(
                status: result.response.statusCode
            )
        }

        guard let token = token(
            from: result.data
        ) else {
            throw TVControlError.permissionDenied(
                "Fire TV accepted the code but did not return a pairing token. Try pairing again."
            )
        }

        let credential = FireTVCredential(
            token: token
        )

        try PairingCredentialStore.save(
            credential,
            platform: .fireTV,
            deviceID: device.id
        )

        self.credential = credential
        pinDisplayed = false

        guard case .valid = await validate(
            token: token
        ) else {
            throw TVControlError.permissionDenied(
                "Fire TV pairing could not be verified. Try again."
            )
        }
    }

    func send(
        _ command: RemoteCommand
    ) async throws {
        guard let token = credential?.token else {
            throw TVControlError.permissionDenied(
                "Pair Orbit with this Fire TV first."
            )
        }

        switch command {
        case .power:
            switch await validate(token: token) {
            case .valid:
                try await navigation(
                    action: "sleep",
                    token: token
                )

            case .unreachable:
                try await wake()

            case .unauthorized:
                throw TVControlError.permissionDenied(
                    "Fire TV no longer recognizes Orbit. Pair it again."
                )
            }

        case .rewind:
            try await media(
                action: "scan",
                direction: "back",
                token: token
            )

        case .fastForward:
            try await media(
                action: "scan",
                direction: "forward",
                token: token
            )

        case .play:
            try await media(
                action: "play",
                token: token
            )

        case .pause:
            try await media(
                action: "pause",
                token: token
            )

        default:
            guard let action = navigationAction(
                for: command
            ) else {
                throw TVControlError.unsupported
            }

            try await navigation(
                action: action,
                token: token
            )
        }
    }

    func beginPress(
        _ command: RemoteCommand
    ) async throws {
        guard let token = credential?.token,
              let action = navigationAction(
                  for: command
              ) else {
            try await send(command)
            return
        }

        try await navigation(
            action: action,
            keyActionType: "keyDown",
            token: token
        )
    }

    func endPress(
        _ command: RemoteCommand
    ) async throws {
        guard let token = credential?.token,
              let action = navigationAction(
                  for: command
              ) else {
            return
        }

        try await navigation(
            action: action,
            keyActionType: "keyUp",
            token: token
        )
    }

    func send(
        text: String
    ) async throws {
        guard let token = credential?.token else {
            throw TVControlError.permissionDenied(
                "Pair Orbit with this Fire TV first."
            )
        }

        let body = try JSONSerialization.data(
            withJSONObject: ["text": text]
        )

        let result = try await request(
            path: "/v1/FireTV/keyboard",
            method: "POST",
            body: body,
            token: token
        )
        try requireSuccess(result)
    }

    func apps() async throws -> [TVApp] {
        guard let token = credential?.token else {
            throw TVControlError.permissionDenied(
                "Pair Orbit with this Fire TV first."
            )
        }

        let result = try await request(
            path: "/v1/FireTV/appsV2",
            method: "GET",
            body: nil,
            token: token
        )

        guard (200..<300).contains(
            result.response.statusCode
        ) else {
            throw apiError(
                status: result.response.statusCode
            )
        }

        return parseApps(
            data: result.data
        )
    }

    func inputs() async throws -> [TVInput] {
        []
    }

    func launch(
        app: TVApp
    ) async throws {
        guard let token = credential?.token,
              let encoded = app.id.addingPercentEncoding(
                  withAllowedCharacters: .urlPathAllowed
              ) else {
            throw TVControlError.unsupported
        }

        let result = try await request(
            path: "/v1/FireTV/app/\(encoded)",
            method: "POST",
            body: nil,
            token: token
        )
        try requireSuccess(result)
    }

    func select(
        input: TVInput
    ) async throws {
        throw TVControlError.unsupported
    }

    func probeWakeEndpoint() async -> Bool {
        do {
            let result = try await wakeRequest()
            return (200..<300).contains(
                result.response.statusCode
            )
        } catch {
            return false
        }
    }

    private var capabilities: Set<TVCapability> {
        [
            .directionalNavigation,
            .touchpad,
            .keyboard,
            .power,
            .volume,
            .mute,
            .appLaunching,
            .playback
        ]
    }

    private func connectedInfo() -> TVConnectionInfo {
        device.capabilities = capabilities

        return TVConnectionInfo(
            state: .connected,
            capabilities: capabilities,
            pairingRequirement: .none
        )
    }

    private func displayPin() async throws {
        let body = try JSONSerialization.data(
            withJSONObject: [
                "friendlyName": "Orbit"
            ]
        )

        let result = try await request(
            path: "/v1/FireTV/pin/display",
            method: "POST",
            body: body,
            token: nil
        )

        guard (200..<300).contains(
            result.response.statusCode
        ) else {
            throw pairingError(
                status: result.response.statusCode
            )
        }
    }

    private func wake() async throws {
        let result = try await wakeRequest()

        guard (200..<300).contains(
            result.response.statusCode
        ) else {
            throw TVControlError.unreachable
        }
    }

    private func wakeRequest() async throws -> FireHTTPResult {
        guard let url = URL(
            string:
                "http://\(device.host):\(Self.wakePort)/apps/FireTVRemote"
        ) else {
            throw TVControlError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data()

        do {
            let (data, response) = try await session.data(
                for: request
            )

            guard let http = response as? HTTPURLResponse else {
                throw TVControlError.invalidResponse
            }

            return FireHTTPResult(
                data: data,
                response: http
            )
        } catch let error as TVControlError {
            throw error
        } catch {
            throw TVControlError.unreachable
        }
    }

    private func validate(
        token: String
    ) async -> FireValidation {
        do {
            let result = try await request(
                path: "/v1/FireTV/appsV2",
                method: "GET",
                body: nil,
                token: token
            )

            if (200..<300).contains(
                result.response.statusCode
            ) {
                return .valid
            }

            if result.response.statusCode == 401 ||
                result.response.statusCode == 403 {
                return .unauthorized
            }

            return .unreachable
        } catch {
            return .unreachable
        }
    }

    private func navigation(
        action: String,
        keyActionType: String? = nil,
        token: String
    ) async throws {
        var body: Data?

        if let keyActionType {
            body = try JSONSerialization.data(
                withJSONObject: [
                    "keyActionType": keyActionType
                ]
            )
        }

        let result = try await request(
            path: "/v1/FireTV",
            method: "POST",
            queryItems: [
                URLQueryItem(
                    name: "action",
                    value: action
                )
            ],
            body: body,
            token: token
        )
        try requireSuccess(result)
    }

    private func media(
        action: String,
        direction: String? = nil,
        token: String
    ) async throws {
        var queryItems = [
            URLQueryItem(
                name: "action",
                value: action
            )
        ]

        if let direction {
            queryItems.append(
                URLQueryItem(
                    name: "direction",
                    value: direction
                )
            )
        }

        let result = try await request(
            path: "/v1/media",
            method: "POST",
            queryItems: queryItems,
            body: nil,
            token: token
        )
        try requireSuccess(result)
    }

    private func navigationAction(
        for command: RemoteCommand
    ) -> String? {
        switch command {
        case .up:
            return "dpad_up"
        case .down:
            return "dpad_down"
        case .left:
            return "dpad_left"
        case .right:
            return "dpad_right"
        case .select:
            return "select"
        case .back:
            return "back"
        case .home:
            return "home"
        case .volumeUp:
            return "volume_up"
        case .volumeDown:
            return "volume_down"
        case .mute:
            return "mute"
        default:
            return nil
        }
    }

    private func request(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        body: Data?,
        token: String?
    ) async throws -> FireHTTPResult {
        var components = URLComponents()
        components.scheme = "https"
        components.host = device.host
        components.port = Self.lightningPort
        components.path = path
        components.queryItems = queryItems.isEmpty
            ? nil
            : queryItems

        guard let url = components.url else {
            throw TVControlError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(
            Self.apiKey,
            forHTTPHeaderField: "X-Api-Key"
        )
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )

        if let token {
            request.setValue(
                token,
                forHTTPHeaderField: "X-Client-Token"
            )
        }

        do {
            let (data, response) = try await session.data(
                for: request
            )

            guard let http = response as? HTTPURLResponse else {
                throw TVControlError.invalidResponse
            }

            return FireHTTPResult(
                data: data,
                response: http
            )
        } catch let error as TVControlError {
            throw error
        } catch {
            throw TVControlError.unreachable
        }
    }

    private func requireSuccess(
        _ result: FireHTTPResult
    ) throws {
        guard (200..<300).contains(
            result.response.statusCode
        ) else {
            throw apiError(
                status: result.response.statusCode
            )
        }
    }

    private func apiError(
        status: Int
    ) -> TVControlError {
        if status == 401 || status == 403 {
            return .permissionDenied(
                "Fire TV no longer recognizes Orbit. Pair it again."
            )
        }

        return .unreachable
    }

    private func pairingError(
        status: Int
    ) -> TVControlError {
        if status == 401 ||
            status == 403 ||
            status == 422 {
            return .permissionDenied(
                "Fire TV rejected the pairing request. Check the code and try again."
            )
        }

        return .unreachable
    }

    private func token(
        from data: Data
    ) -> String? {
        guard !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(
                  with: data
              ) as? [String: Any] else {
            return nil
        }

        for key in [
            "clientToken",
            "client_token",
            "token",
            "description"
        ] {
            guard let value = object[key] as? String else {
                continue
            }

            let trimmed = value.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            if !trimmed.isEmpty &&
                trimmed.caseInsensitiveCompare("OK") != .orderedSame {
                return trimmed
            }
        }

        return nil
    }

    private func parseApps(
        data: Data
    ) -> [TVApp] {
        guard let json = try? JSONSerialization.jsonObject(
            with: data
        ) else {
            return []
        }

        let rawApps: [[String: Any]]

        if let array = json as? [[String: Any]] {
            rawApps = array
        } else if let object = json as? [String: Any] {
            rawApps = [
                "apps",
                "appsV2",
                "result"
            ]
            .compactMap {
                object[$0] as? [[String: Any]]
            }
            .first ?? []
        } else {
            rawApps = []
        }

        return rawApps.compactMap { item in
            guard let id = item["appId"] as? String,
                  !id.isEmpty else {
                return nil
            }

            if item["isShortcutApp"] as? Bool == true {
                return nil
            }

            if let installed = item["isInstalled"] as? Bool,
               !installed {
                return nil
            }

            return TVApp(
                id: id,
                name:
                    (item["name"] as? String) ??
                    id
            )
        }
        .sorted {
            $0.name.localizedCaseInsensitiveCompare(
                $1.name
            ) == .orderedAscending
        }
    }
}

private struct FireTVCredential: Codable {
    let token: String
}

private struct FireHTTPResult {
    let data: Data
    let response: HTTPURLResponse
}

private enum FireValidation {
    case valid
    case unauthorized
    case unreachable
}

private final class FireTVLocalTrustDelegate:
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
        if parts[0] == 100 &&
            (64...127).contains(parts[1]) {
            return true
        }

        return false
    }
}
