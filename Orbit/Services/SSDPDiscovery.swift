import Foundation
import Darwin

struct SSDPResponse: Hashable, Sendable {
    let location: URL
    let usn: String?
    let searchTarget: String?
    let server: String?

    var platformHint: TVPlatform? {
        let fingerprint = [
            usn,
            searchTarget,
            server,
            location.absoluteString
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()

        if fingerprint.contains("roku") {
            return .roku
        }

        if fingerprint.contains("samsung") {
            return .samsung
        }

        if fingerprint.contains("webos") ||
            fingerprint.contains("lge") ||
            fingerprint.contains("lg electronics") {
            return .lgWebOS
        }

        return nil
    }
}

enum SSDPScanner {
    private static let multicastAddress = "239.255.255.250"
    private static let multicastPort: UInt16 = 1900

    static func scan(timeout: TimeInterval = 1.8) async -> [SSDPResponse] {
        await Task.detached(priority: .userInitiated) {
            scanBlocking(timeout: timeout)
        }.value
    }

    private static func scanBlocking(timeout: TimeInterval) -> [SSDPResponse] {
        let socketFD = Darwin.socket(
            AF_INET,
            Int32(SOCK_DGRAM.rawValue),
            IPPROTO_UDP
        )

        guard socketFD >= 0 else {
            return []
        }

        defer {
            Darwin.close(socketFD)
        }

        var receiveTimeout = timeval(tv_sec: 0, tv_usec: 200_000)
        withUnsafePointer(to: &receiveTimeout) { pointer in
            _ = Darwin.setsockopt(
                socketFD,
                SOL_SOCKET,
                SO_RCVTIMEO,
                pointer,
                socklen_t(MemoryLayout<timeval>.size)
            )
        }

        var destination = sockaddr_in()
        destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        destination.sin_family = sa_family_t(AF_INET)
        destination.sin_port = in_port_t(multicastPort).bigEndian

        guard inet_pton(AF_INET, multicastAddress, &destination.sin_addr) == 1 else {
            return []
        }

        for searchTarget in ["roku:ecp", "ssdp:all"] {
            let request = [
                "M-SEARCH * HTTP/1.1",
                "HOST: \(multicastAddress):\(multicastPort)",
                "MAN: \"ssdp:discover\"",
                "MX: 1",
                "ST: \(searchTarget)",
                "",
                ""
            ].joined(separator: "\r\n")

            guard let data = request.data(using: .utf8) else { continue }

            data.withUnsafeBytes { bytes in
                withUnsafePointer(to: &destination) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                        _ = Darwin.sendto(
                            socketFD,
                            bytes.baseAddress,
                            bytes.count,
                            0,
                            address,
                            socklen_t(MemoryLayout<sockaddr_in>.size)
                        )
                    }
                }
            }
        }

        let deadline = Date().addingTimeInterval(timeout)
        var responses: [String: SSDPResponse] = [:]
        var buffer = [UInt8](repeating: 0, count: 65_535)

        while Date() < deadline {
            var source = sockaddr_storage()
            var sourceLength = socklen_t(MemoryLayout<sockaddr_storage>.size)

            let received: Int = buffer.withUnsafeMutableBytes { bytes in
                withUnsafeMutablePointer(to: &source) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                        Darwin.recvfrom(
                            socketFD,
                            bytes.baseAddress,
                            bytes.count,
                            0,
                            address,
                            &sourceLength
                        )
                    }
                }
            }

            if received > 0 {
                let data = Data(buffer.prefix(received))

                if let response = parse(data: data) {
                    let key = response.usn ?? response.location.absoluteString
                    responses[key] = response
                }

                continue
            }

            if received < 0,
               errno != EAGAIN,
               errno != EWOULDBLOCK {
                break
            }
        }

        return Array(responses.values)
    }

    private static func parse(data: Data) -> SSDPResponse? {
        guard let text = String(data: data, encoding: .utf8) else {
            return nil
        }

        var headers: [String: String] = [:]

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let separator = line.firstIndex(of: ":") else { continue }

            let name = String(line[..<separator])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            let valueStart = line.index(after: separator)
            let value = String(line[valueStart...])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !name.isEmpty, !value.isEmpty {
                headers[name] = value
            }
        }

        guard let locationString = headers["location"],
              let location = URL(string: locationString) else {
            return nil
        }

        return SSDPResponse(
            location: location,
            usn: headers["usn"],
            searchTarget: headers["st"],
            server: headers["server"]
        )
    }
}
