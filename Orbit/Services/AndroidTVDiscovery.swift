import Foundation
@preconcurrency import Network

enum AndroidTVBonjourScanner {
    private static let serviceType = "_androidtvremote2._tcp"

    static func scan(
        timeout: TimeInterval = 1.8
    ) async -> [TVDevice] {
        let endpoints = await browseEndpoints(timeout: timeout)

        return await withTaskGroup(
            of: TVDevice?.self,
            returning: [TVDevice].self
        ) { group in
            for endpoint in endpoints {
                group.addTask {
                    await resolve(endpoint: endpoint)
                }
            }

            var devices: [TVDevice] = []

            for await device in group {
                if let device {
                    devices.append(device)
                }
            }

            return devices
        }
    }

    private static func browseEndpoints(
        timeout: TimeInterval
    ) async -> [NWEndpoint] {
        await withCheckedContinuation { continuation in
            let queue = DispatchQueue(
                label: "orbit.discovery.androidtv"
            )

            let browser = NWBrowser(
                for: .bonjour(
                    type: serviceType,
                    domain: nil
                ),
                using: .tcp
            )

            let session = AndroidTVBrowseSession(
                browser: browser,
                continuation: continuation
            )

            browser.browseResultsChangedHandler = {
                results,
                _
                in
                session.update(
                    endpoints: results.map(\.endpoint)
                )
            }

            browser.stateUpdateHandler = { state in
                switch state {
                case .failed, .cancelled:
                    session.finish()
                default:
                    break
                }
            }

            browser.start(queue: queue)

            queue.asyncAfter(
                deadline: .now() + timeout
            ) {
                session.finish()
            }
        }
    }

    private static func resolve(
        endpoint: NWEndpoint
    ) async -> TVDevice? {
        let serviceName: String

        switch endpoint {
        case .service(let name, _, _, _):
            serviceName = name
        default:
            serviceName = "Android TV"
        }

        guard let resolved = await EndpointResolver.resolve(
            endpoint: endpoint,
            timeout: 1.2
        ) else {
            return nil
        }

        return TVDevice(
            id: "androidtv-\(serviceName.lowercased())",
            name: serviceName,
            platform: .androidTV,
            host: resolved.host,
            port: Int(resolved.port),
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
    }
}

enum LocalTCPProbe {
    static func isReachable(
        host: String,
        port: UInt16,
        timeout: TimeInterval = 0.8
    ) async -> Bool {
        guard let nwPort = NWEndpoint.Port(
            rawValue: port
        ) else {
            return false
        }

        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: nwPort
        )

        return await EndpointResolver.resolve(
            endpoint: endpoint,
            timeout: timeout
        ) != nil
    }
}

private struct ResolvedEndpoint: Sendable {
    let host: String
    let port: UInt16
}

private enum EndpointResolver {
    static func resolve(
        endpoint: NWEndpoint,
        timeout: TimeInterval
    ) async -> ResolvedEndpoint? {
        await withCheckedContinuation { continuation in
            let queue = DispatchQueue(
                label: "orbit.discovery.resolve"
            )
            let connection = NWConnection(
                to: endpoint,
                using: .tcp
            )
            let gate = EndpointResolutionGate(
                connection: connection,
                continuation: continuation
            )

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    gate.finish(
                        resolved: resolvedEndpoint(
                            for: connection,
                            fallback: endpoint
                        )
                    )

                case .failed, .cancelled:
                    gate.finish(resolved: nil)

                default:
                    break
                }
            }

            connection.start(queue: queue)

            queue.asyncAfter(
                deadline: .now() + timeout
            ) {
                gate.finish(resolved: nil)
            }
        }
    }

    private static func resolvedEndpoint(
        for connection: NWConnection,
        fallback: NWEndpoint
    ) -> ResolvedEndpoint? {
        let candidates = [
            connection.currentPath?.remoteEndpoint,
            fallback
        ]

        for candidate in candidates {
            guard let candidate else { continue }

            if case .hostPort(
                let host,
                let port
            ) = candidate {
                return ResolvedEndpoint(
                    host: String(describing: host),
                    port: port.rawValue
                )
            }
        }

        return nil
    }
}

private final class AndroidTVBrowseSession: @unchecked Sendable {
    private let lock = NSLock()
    private let browser: NWBrowser
    private var continuation:
        CheckedContinuation<[NWEndpoint], Never>?
    private var endpoints: [NWEndpoint] = []
    private var finished = false

    init(
        browser: NWBrowser,
        continuation:
            CheckedContinuation<[NWEndpoint], Never>
    ) {
        self.browser = browser
        self.continuation = continuation
    }

    func update(
        endpoints: [NWEndpoint]
    ) {
        lock.lock()
        defer { lock.unlock() }

        guard !finished else { return }
        self.endpoints = endpoints
    }

    func finish() {
        lock.lock()

        guard !finished else {
            lock.unlock()
            return
        }

        finished = true
        let endpoints = self.endpoints
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        browser.cancel()
        continuation?.resume(returning: endpoints)
    }
}

private final class EndpointResolutionGate: @unchecked Sendable {
    private let lock = NSLock()
    private let connection: NWConnection
    private var continuation:
        CheckedContinuation<ResolvedEndpoint?, Never>?
    private var finished = false

    init(
        connection: NWConnection,
        continuation:
            CheckedContinuation<ResolvedEndpoint?, Never>
    ) {
        self.connection = connection
        self.continuation = continuation
    }

    func finish(
        resolved: ResolvedEndpoint?
    ) {
        lock.lock()

        guard !finished else {
            lock.unlock()
            return
        }

        finished = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        connection.stateUpdateHandler = nil
        connection.cancel()
        continuation?.resume(returning: resolved)
    }
}
