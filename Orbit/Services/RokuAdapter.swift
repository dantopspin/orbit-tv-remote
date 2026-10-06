import Foundation

final class RokuAdapter: NSObject, TVControlling {
    private(set) var device: TVDevice

    private static let localSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 2.5
        configuration.timeoutIntervalForResource = 4.0
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    private let session: URLSession
    private var deviceInfo: RokuDeviceInfo?

    init(device: TVDevice, session: URLSession? = nil) {
        self.device = device
        self.session = session ?? Self.localSession
    }

    func connect() async throws -> TVConnectionInfo {
        let data = try await get("query/device-info")
        let info = try RokuDeviceInfoParser(data: data).parse()

        guard info.looksLikeRoku else {
            throw TVControlError.invalidResponse
        }

        deviceInfo = info
        device = resolvedDevice(from: info)

        return TVConnectionInfo(
            state: info.isPoweredOff ? .off : .connected,
            capabilities: device.capabilities,
            pairingRequirement: .none
        )
    }

    func send(_ command: RemoteCommand) async throws {
        let key = try key(for: command)
        try await post("keypress/\(key)")

        if command == .power, deviceInfo?.isTV == true {
            let wasPoweredOff = deviceInfo?.isPoweredOff == true
            deviceInfo?.powerMode = wasPoweredOff ? "PowerOn" : "PowerOff"
        }
    }

    func beginPress(_ command: RemoteCommand) async throws {
        let key = try key(for: command)
        try await post("keydown/\(key)")
    }

    func endPress(_ command: RemoteCommand) async throws {
        let key = try key(for: command)
        try await post("keyup/\(key)")
    }

    func send(text: String) async throws {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")

        for character in text {
            let literal = String(character)

            guard let encoded = literal.addingPercentEncoding(withAllowedCharacters: allowed) else {
                throw TVControlError.invalidResponse
            }

            try await post("keypress/Lit_\(encoded)")
        }
    }

    func apps() async throws -> [TVApp] {
        let data = try await get("query/apps")
        return RokuAppsParser(data: data).parse()
    }

    func inputs() async throws -> [TVInput] {
        guard deviceInfo?.isTV == true else {
            return []
        }

        return [
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
        guard deviceInfo?.isTV == true else {
            throw TVControlError.unsupported
        }

        try await post("keypress/\(input.id)")
    }

    private func resolvedDevice(from info: RokuDeviceInfo) -> TVDevice {
        let stableID = info.serialNumber ?? info.deviceID
        let manualID = "roku-\(device.host)"

        let resolvedID: String

        if let stableID,
           !stableID.isEmpty {
            resolvedID =
                "roku-\(stableID.lowercased())"
        } else {
            resolvedID = device.id
        }

        var aliases = device.discoveryAliases

        if device.id != manualID,
           device.id != resolvedID {
            aliases.insert(device.id)
        }

        var capabilities: Set<TVCapability> = [
            .directionalNavigation,
            .touchpad,
            .keyboard,
            .appLaunching,
            .playback
        ]

        if info.isTV {
            capabilities.formUnion([
                .power,
                .volume,
                .mute,
                .inputSelection,
                .channels
            ])
        }

        return TVDevice(
            id: resolvedID,
            name: info.bestName ?? (info.isTV ? "Roku TV" : "Roku"),
            platform: .roku,
            host: device.host,
            port: device.port ?? 8060,
            roomName: device.roomName,
            discoveryIDs:
                aliases.isEmpty ? nil : aliases,
            capabilities: capabilities
        )
    }

    private func key(for command: RemoteCommand) throws -> String {
        switch command {
        case .power:
            guard deviceInfo?.isTV == true else {
                throw TVControlError.unsupported
            }
            return deviceInfo?.isPoweredOff == true ? "PowerOn" : "PowerOff"
        case .up:
            return "Up"
        case .down:
            return "Down"
        case .left:
            return "Left"
        case .right:
            return "Right"
        case .select:
            return "Select"
        case .back:
            return "Back"
        case .home:
            return "Home"
        case .volumeUp:
            guard deviceInfo?.isTV == true else { throw TVControlError.unsupported }
            return "VolumeUp"
        case .volumeDown:
            guard deviceInfo?.isTV == true else { throw TVControlError.unsupported }
            return "VolumeDown"
        case .mute:
            guard deviceInfo?.isTV == true else { throw TVControlError.unsupported }
            return "VolumeMute"
        case .rewind:
            return "Rev"
        case .play, .pause:
            return "Play"
        case .fastForward:
            return "Fwd"
        case .channelUp:
            guard deviceInfo?.isTV == true else { throw TVControlError.unsupported }
            return "ChannelUp"
        case .channelDown:
            guard deviceInfo?.isTV == true else { throw TVControlError.unsupported }
            return "ChannelDown"
        }
    }

    private func get(_ path: String) async throws -> Data {
        guard let url = endpoint(path) else {
            throw TVControlError.invalidResponse
        }

        let (data, response) = try await session.data(from: url)
        try validate(response)
        return data
    }

    private func post(_ path: String) async throws {
        guard let url = endpoint(path) else {
            throw TVControlError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data()

        let (_, response) = try await session.data(for: request)
        try validate(response)
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw TVControlError.invalidResponse
        }

        if http.statusCode == 401 || http.statusCode == 403 {
            throw TVControlError.permissionDenied(
                "Roku mobile-app control is disabled or limited. On your Roku, allow control by mobile apps, then try again."
            )
        }

        guard (200..<300).contains(http.statusCode) else {
            throw TVControlError.rejected(
                status: http.statusCode,
                message: "Roku rejected that command."
            )
        }
    }

    private func endpoint(_ path: String) -> URL? {
        let port = device.port ?? 8060
        return URL(string: "http://\(device.host):\(port)/\(path)")
    }
}

private struct RokuDeviceInfo {
    var serialNumber: String?
    var deviceID: String?
    var userDeviceName: String?
    var friendlyDeviceName: String?
    var modelName: String?
    var isTV: Bool = false
    var powerMode: String?
    var rootElement: String?

    var looksLikeRoku: Bool {
        rootElement == "device-info" &&
        (serialNumber != nil || deviceID != nil || modelName != nil)
    }

    var bestName: String? {
        [userDeviceName, friendlyDeviceName, modelName]
            .compactMap { value in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
                return (trimmed?.isEmpty == false) ? trimmed : nil
            }
            .first
    }

    var isPoweredOff: Bool {
        guard let powerMode else { return false }
        return powerMode.lowercased().contains("off")
    }
}

private final class RokuDeviceInfoParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var info = RokuDeviceInfo()
    private var currentElement: String?
    private var currentText = ""

    init(data: Data) {
        self.data = data
    }

    func parse() throws -> RokuDeviceInfo {
        let parser = XMLParser(data: data)
        parser.delegate = self

        guard parser.parse(), info.looksLikeRoku else {
            throw TVControlError.invalidResponse
        }

        return info
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if info.rootElement == nil {
            info.rootElement = elementName
        }

        currentElement = elementName
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
        guard currentElement == elementName else { return }

        let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "serial-number":
            info.serialNumber = value
        case "device-id":
            info.deviceID = value
        case "user-device-name":
            info.userDeviceName = value
        case "friendly-device-name":
            info.friendlyDeviceName = value
        case "model-name":
            info.modelName = value
        case "is-tv":
            info.isTV = value.lowercased() == "true"
        case "power-mode":
            info.powerMode = value
        default:
            break
        }

        currentElement = nil
        currentText = ""
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
