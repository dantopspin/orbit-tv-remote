import Foundation

final class RokuAdapter: NSObject, TVControlling {
    let device: TVDevice
    private static let localSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 2.5
        configuration.timeoutIntervalForResource = 4.0
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    private let session: URLSession

    init(device: TVDevice, session: URLSession? = nil) {
        self.device = device
        self.session = session ?? Self.localSession
    }

    func connect() async throws -> TVConnectionInfo {
        guard let url = endpoint("query/device-info") else {
            throw TVControlError.invalidResponse
        }

        let (_, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw TVControlError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            throw TVControlError.unreachable
        }

        return TVConnectionInfo(
            state: .connected,
            capabilities: device.capabilities,
            pairingRequirement: .none
        )
    }

    func beginPress(_ command: RemoteCommand) async throws {
        let key = try key(for: command)
        try await post("keydown/\(key)")
    }

    func endPress(_ command: RemoteCommand) async throws {
        let key = try key(for: command)
        try await post("keyup/\(key)")
    }

    func send(_ command: RemoteCommand) async throws {
        try await post("keypress/\(try key(for: command))")
    }

    func send(text: String) async throws {
        for character in text {
            let raw = "Lit_\(character)"
            guard let encoded = raw.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
                continue
            }
            try await post("keypress/\(encoded)")
        }
    }

    func apps() async throws -> [TVApp] {
        guard let url = endpoint("query/apps") else {
            throw TVControlError.invalidResponse
        }

        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw TVControlError.unreachable
        }

        return RokuAppsParser(data: data).parse()
    }

    func inputs() async throws -> [TVInput] {
        [
            TVInput(id: "InputTuner", name: "TV"),
            TVInput(id: "InputHDMI1", name: "HDMI 1"),
            TVInput(id: "InputHDMI2", name: "HDMI 2"),
            TVInput(id: "InputHDMI3", name: "HDMI 3"),
            TVInput(id: "InputHDMI4", name: "HDMI 4"),
            TVInput(id: "InputAV1", name: "AV")
        ]
    }

    func launch(app: TVApp) async throws {
        try await post("launch/\(app.id)")
    }

    func select(input: TVInput) async throws {
        try await post("keypress/\(input.id)")
    }

    private func post(_ path: String) async throws {
        guard let url = endpoint(path) else {
            throw TVControlError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data()

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw TVControlError.unreachable
        }
    }

    private func key(for command: RemoteCommand) throws -> String {
        switch command {
        case .power: return "PowerOff"
        case .up: return "Up"
        case .down: return "Down"
        case .left: return "Left"
        case .right: return "Right"
        case .select: return "Select"
        case .back: return "Back"
        case .home: return "Home"
        case .volumeUp: return "VolumeUp"
        case .volumeDown: return "VolumeDown"
        case .mute: return "VolumeMute"
        case .rewind: return "Rev"
        case .play, .pause: return "Play"
        case .fastForward: return "Fwd"
        case .channelUp: return "ChannelUp"
        case .channelDown: return "ChannelDown"
        }
    }

    private func endpoint(_ path: String) -> URL? {
        let port = device.port ?? 8060
        return URL(string: "http://\(device.host):\(port)/\(path)")
    }
}

private final class RokuAppsParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var apps: [TVApp] = []
    private var currentID: String?
    private var currentText = ""

    init(data: Data) {
        self.data = data
    }

    func parse() -> [TVApp] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return apps
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName == "app" else { return }
        currentID = attributeDict["id"]
        currentText = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard elementName == "app", let id = currentID else { return }

        let name = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            apps.append(TVApp(id: id, name: name))
        }

        currentID = nil
        currentText = ""
    }
}
