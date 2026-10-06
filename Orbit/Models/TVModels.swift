import Foundation

enum TVPlatform: String, Codable, CaseIterable, Hashable, Sendable {
    case roku
    case samsung
    case lgWebOS
    case androidTV
    case fireTV
    case vidaa
    case vizio
    case philips
    case unknown

    var displayName: String {
        switch self {
        case .roku: return "Roku"
        case .samsung: return "Samsung"
        case .lgWebOS: return "LG webOS"
        case .androidTV: return "Google / Android TV"
        case .fireTV: return "Fire TV"
        case .vidaa: return "VIDAA"
        case .vizio: return "Vizio"
        case .philips: return "Philips"
        case .unknown: return "Smart TV"
        }
    }
}

enum TVCapability: String, Codable, Hashable, Sendable {
    case directionalNavigation
    case touchpad
    case keyboard
    case power
    case volume
    case mute
    case inputSelection
    case appLaunching
    case playback
    case channels
    case wakeOnLAN
}

struct TVDevice: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var name: String
    var platform: TVPlatform
    var host: String
    var port: Int?
    var roomName: String?
    var capabilities: Set<TVCapability>

    init(
        id: String,
        name: String,
        platform: TVPlatform,
        host: String,
        port: Int? = nil,
        roomName: String? = nil,
        capabilities: Set<TVCapability> = []
    ) {
        self.id = id
        self.name = name
        self.platform = platform
        self.host = host
        self.port = port
        self.roomName = roomName
        self.capabilities = capabilities
    }
}

enum RemoteCommand: String, CaseIterable, Sendable {
    case power
    case up
    case down
    case left
    case right
    case select
    case back
    case home
    case volumeUp
    case volumeDown
    case mute
    case rewind
    case play
    case pause
    case fastForward
    case channelUp
    case channelDown
}

struct TVApp: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
}

struct TVInput: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
}

enum TVConnectionState: Equatable, Sendable {
    case connecting
    case connected
    case off
    case unavailable

    var label: String {
        switch self {
        case .connecting: return "Connecting…"
        case .connected: return "On"
        case .off: return "Off"
        case .unavailable: return "Not reachable"
        }
    }
}


enum TVPairingRequirement: Equatable, Sendable {
    case none
    case confirmation(message: String?)
    case pin(length: Int?, message: String?)
}

enum TVPairingResponse: Equatable, Sendable {
    case confirmed
    case pin(String)
}

struct TVConnectionInfo: Equatable, Sendable {
    var state: TVConnectionState
    var capabilities: Set<TVCapability>
    var pairingRequirement: TVPairingRequirement

    init(
        state: TVConnectionState = .connected,
        capabilities: Set<TVCapability>,
        pairingRequirement: TVPairingRequirement = .none
    ) {
        self.state = state
        self.capabilities = capabilities
        self.pairingRequirement = pairingRequirement
    }
}

enum RemoteControlMode: String, Codable, CaseIterable, Hashable, Sendable {
    case dpad
    case touchpad

    var title: String {
        switch self {
        case .dpad: return "D-pad"
        case .touchpad: return "Touchpad"
        }
    }
}

struct RemoteCustomizationPreferences: Codable, Equatable, Sendable {
    var defaultMode: RemoteControlMode = .dpad
    var showInput = true
    var showPlayback = true
    var showKeyboard = true
    var showApps = true
}

enum RemoteFavoriteKind: String, Codable, Hashable, Sendable {
    case app
    case input
}

struct RemoteFavorite: Identifiable, Codable, Hashable, Sendable {
    var id: String { "\(kind.rawValue)|\(targetID)" }

    let kind: RemoteFavoriteKind
    let targetID: String
    let name: String
}
