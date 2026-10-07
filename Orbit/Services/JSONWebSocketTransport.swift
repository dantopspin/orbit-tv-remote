import Foundation

@MainActor
final class JSONWebSocketTransport {
    typealias CloseHandler = @MainActor (Error?) -> Void
    typealias EventHandler = @MainActor (Data) -> Void

    var onUnexpectedClose: CloseHandler?
    var onEvent: EventHandler? {
        didSet {
            if onEvent != nil {
                bufferedEvents.removeAll()
            }
        }
    }

    private let url: URL
    private let session: URLSession

    private var webSocketTask: URLSessionWebSocketTask?
    private var readerTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var intentionallyClosed = false
    private var invalidated = false

    private struct PendingRequest {
        let continuation: CheckedContinuation<Data, Error>
        let timeoutTask: Task<Void, Never>
    }

    private var pendingRequests: [String: PendingRequest] = [:]
    private var retiredRequestIDs: [String] = []

    private var bufferedEvents: [Data] = []
    private var eventContinuation: CheckedContinuation<Data, Error>?
    private var eventTimeoutTask: Task<Void, Never>?

    init(
        url: URL,
        configuration: URLSessionConfiguration,
        delegate: URLSessionDelegate? = nil
    ) {
        self.url = url
        self.session = URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: nil
        )
    }

    func start() {
        guard webSocketTask == nil,
              !invalidated else {
            return
        }

        intentionallyClosed = false

        let task = session.webSocketTask(with: url)
        webSocketTask = task
        task.resume()

        readerTask = Task { @MainActor [weak self] in
            await self?.readLoop()
        }

        pingTask = Task { @MainActor [weak self] in
            await self?.pingLoop()
        }
    }

    func disconnect() {
        intentionallyClosed = true
        invalidated = true

        readerTask?.cancel()
        readerTask = nil

        pingTask?.cancel()
        pingTask = nil

        webSocketTask?.cancel(
            with: .normalClosure,
            reason: nil
        )
        webSocketTask = nil

        session.invalidateAndCancel()

        failAllPending(with: CancellationError())
        failEventWaiter(with: CancellationError())
        bufferedEvents.removeAll()
        retiredRequestIDs.removeAll()
    }

    func sendJSONObject(
        _ object: [String: Any]
    ) async throws {
        guard let webSocketTask else {
            throw TVControlError.unreachable
        }

        let data = try JSONSerialization.data(
            withJSONObject: object
        )

        guard let string = String(
            data: data,
            encoding: .utf8
        ) else {
            throw TVControlError.invalidResponse
        }

        do {
            try await webSocketTask.send(
                .string(string)
            )
        } catch {
            throw TVControlError.unreachable
        }
    }

    func requestJSONObject(
        _ object: [String: Any],
        id: String,
        timeout: TimeInterval = 8
    ) async throws -> Data {
        guard webSocketTask != nil else {
            throw TVControlError.unreachable
        }

        guard pendingRequests[id] == nil else {
            throw TVControlError.invalidResponse
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Data, Error>) in

                let timeoutTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(
                        nanoseconds: Self.nanoseconds(
                            for: timeout
                        )
                    )

                    guard !Task.isCancelled else {
                        return
                    }

                    self?.failPendingRequest(
                        id: id,
                        error: TVControlError.unreachable
                    )
                }

                pendingRequests[id] = PendingRequest(
                    continuation: continuation,
                    timeoutTask: timeoutTask
                )

                Task { @MainActor [weak self] in
                    guard let self else { return }

                    do {
                        try await self.sendJSONObject(
                            object
                        )
                    } catch {
                        self.failPendingRequest(
                            id: id,
                            error: error
                        )
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.failPendingRequest(
                    id: id,
                    error: CancellationError()
                )
            }
        }
    }

    func nextEvent(
        timeout: TimeInterval = 60
    ) async throws -> Data {
        if !bufferedEvents.isEmpty {
            return bufferedEvents.removeFirst()
        }

        guard eventContinuation == nil else {
            throw TVControlError.invalidResponse
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Data, Error>) in

                eventContinuation = continuation

                eventTimeoutTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(
                        nanoseconds: Self.nanoseconds(
                            for: timeout
                        )
                    )

                    guard !Task.isCancelled else {
                        return
                    }

                    self?.failEventWaiter(
                        with: TVControlError.unreachable
                    )
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.failEventWaiter(
                    with: CancellationError()
                )
            }
        }
    }

    private func readLoop() async {
        guard let webSocketTask else { return }

        while !Task.isCancelled {
            do {
                let message = try await webSocketTask.receive()
                let data = try Self.data(from: message)
                route(data)
            } catch is CancellationError {
                return
            } catch {
                handleUnexpectedClose(error)
                return
            }
        }
    }

    private func route(_ data: Data) {
        if let id = Self.messageID(from: data) {
            if let pending = pendingRequests.removeValue(
                forKey: id
            ) {
                pending.timeoutTask.cancel()
                pending.continuation.resume(
                    returning: data
                )
                return
            }

            if let index = retiredRequestIDs.firstIndex(
                of: id
            ) {
                retiredRequestIDs.remove(
                    at: index
                )
                return
            }
        }

        if let eventContinuation {
            self.eventContinuation = nil
            eventTimeoutTask?.cancel()
            eventTimeoutTask = nil

            eventContinuation.resume(
                returning: data
            )
            return
        }

        if let onEvent {
            onEvent(data)
            return
        }

        bufferedEvents.append(data)

        if bufferedEvents.count > 32 {
            bufferedEvents.removeFirst(
                bufferedEvents.count - 32
            )
        }
    }

    private func handleUnexpectedClose(
        _ error: Error
    ) {
        guard !intentionallyClosed else {
            return
        }

        intentionallyClosed = true

        pingTask?.cancel()
        pingTask = nil

        let closingTask = webSocketTask
        webSocketTask = nil
        closingTask?.cancel(
            with: .goingAway,
            reason: nil
        )

        failAllPending(
            with: TVControlError.unreachable
        )
        failEventWaiter(
            with: TVControlError.unreachable
        )

        onUnexpectedClose?(error)
    }

    private func failPendingRequest(
        id: String,
        error: Error
    ) {
        guard let pending = pendingRequests.removeValue(
            forKey: id
        ) else {
            return
        }

        pending.timeoutTask.cancel()
        retireRequestID(id)
        pending.continuation.resume(
            throwing: error
        )
    }

    private func failAllPending(
        with error: Error
    ) {
        let requests = pendingRequests
        pendingRequests.removeAll()

        for pending in requests.values {
            pending.timeoutTask.cancel()
            pending.continuation.resume(
                throwing: error
            )
        }
    }

    private func failEventWaiter(
        with error: Error
    ) {
        guard let eventContinuation else {
            return
        }

        self.eventContinuation = nil
        eventTimeoutTask?.cancel()
        eventTimeoutTask = nil

        eventContinuation.resume(
            throwing: error
        )
    }

    private func pingLoop() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(
                    nanoseconds: 25_000_000_000
                )

                guard !Task.isCancelled else {
                    return
                }

                try await sendPing()
            } catch is CancellationError {
                return
            } catch {
                handleUnexpectedClose(error)
                return
            }
        }
    }

    private func sendPing() async throws {
        guard let webSocketTask else {
            throw TVControlError.unreachable
        }

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in

            webSocketTask.sendPing { error in
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

    private func retireRequestID(
        _ id: String
    ) {
        guard !retiredRequestIDs.contains(
            id
        ) else {
            return
        }

        retiredRequestIDs.append(id)

        if retiredRequestIDs.count > 64 {
            retiredRequestIDs.removeFirst(
                retiredRequestIDs.count - 64
            )
        }
    }

    private static func data(
        from message: URLSessionWebSocketTask.Message
    ) throws -> Data {
        switch message {
        case .string(let string):
            guard let data = string.data(
                using: .utf8
            ) else {
                throw TVControlError.invalidResponse
            }
            return data

        case .data(let data):
            return data

        @unknown default:
            throw TVControlError.invalidResponse
        }
    }

    private static func messageID(
        from data: Data
    ) -> String? {
        guard let object = try? JSONSerialization.jsonObject(
            with: data
        ) as? [String: Any] else {
            return nil
        }

        return object["id"] as? String
    }

    private static func nanoseconds(
        for timeout: TimeInterval
    ) -> UInt64 {
        UInt64(
            max(0, timeout) * 1_000_000_000
        )
    }
}
