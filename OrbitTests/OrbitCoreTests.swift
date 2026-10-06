import XCTest
@testable import Orbit

final class SSDPResponseTests: XCTestCase {
    func testParsesRokuResponseAndCanonicalizesUSN() throws {
        let payload = """
        HTTP/1.1 200 OK\r
        LOCATION: http://192.168.1.24:8060/\r
        ST: roku:ecp\r
        USN: uuid:roku:ecp:ABC123::roku:ecp\r
        SERVER: Roku/14.0 UPnP/1.0\r
        \r
        """

        let response = try XCTUnwrap(
            SSDPResponse.parse(
                data: Data(payload.utf8)
            )
        )

        XCTAssertEqual(
            response.location.host,
            "192.168.1.24"
        )
        XCTAssertEqual(
            response.location.port,
            8060
        )
        XCTAssertEqual(
            response.platformHint,
            .roku
        )
        XCTAssertEqual(
            response.canonicalUSN,
            "uuid:roku:ecp:abc123"
        )
        XCTAssertEqual(
            response.deduplicationKey,
            "uuid:roku:ecp:abc123"
        )

        let discoveredID =
            "roku-\(response.canonicalUSN ?? "fallback")"
        XCTAssertEqual(
            discoveredID,
            "roku-uuid:roku:ecp:abc123"
        )
    }

    func testRejectsResponseWithoutLocation() {
        let payload = """
        HTTP/1.1 200 OK\r
        ST: ssdp:all\r
        USN: uuid:missing-location\r
        \r
        """

        XCTAssertNil(
            SSDPResponse.parse(
                data: Data(payload.utf8)
            )
        )
    }

    func testSamsungFingerprintIsRecognized() throws {
        let payload = """
        HTTP/1.1 200 OK\r
        LOCATION: http://192.168.1.50:8001/api/v2/\r
        ST: urn:samsung.com:device:RemoteControlReceiver:1\r
        USN: uuid:samsung-tv-123::urn:samsung.com:device:RemoteControlReceiver:1\r
        SERVER: Samsung Tizen\r
        \r
        """

        let response = try XCTUnwrap(
            SSDPResponse.parse(
                data: Data(payload.utf8)
            )
        )

        XCTAssertEqual(
            response.platformHint,
            .samsung
        )
    }
}

@MainActor
final class DeviceStoreTests: XCTestCase {
    func testReconcileMigratesSelectionAndFreeDeviceID() {
        clearDeviceDefaults()
        defer { clearDeviceDefaults() }

        let store = DeviceStore()

        let provisional = TVDevice(
            id: "samsung-192.168.1.10",
            name: "Samsung TV",
            platform: .samsung,
            host: "192.168.1.10"
        )

        store.addOrUpdate(provisional)

        UserDefaults.standard.set(
            provisional.id,
            forKey: AppSettings.Keys.freeDeviceID
        )

        let resolved = TVDevice(
            id: "samsung-stable-123",
            name: "Living Room TV",
            platform: .samsung,
            host: "192.168.1.20",
            capabilities: [
                .directionalNavigation,
                .power
            ]
        )

        store.reconcile(
            oldDeviceID: provisional.id,
            with: resolved
        )

        XCTAssertEqual(
            store.devices.count,
            1
        )
        XCTAssertEqual(
            store.selectedDeviceID,
            resolved.id
        )
        XCTAssertEqual(
            store.selectedDevice?.host,
            "192.168.1.20"
        )
        XCTAssertEqual(
            UserDefaults.standard.string(
                forKey: AppSettings.Keys.freeDeviceID
            ),
            resolved.id
        )
    }

    func testDiscoveryAliasRefreshesSavedTVAfterAddressChange() {
        clearDeviceDefaults()
        defer { clearDeviceDefaults() }

        let store = DeviceStore()

        let discoveryAlias =
            "samsung-uuid:ssdp-123"

        let manuallyResolved = TVDevice(
            id: "samsung-hardware-123",
            name: "Living Room",
            platform: .samsung,
            host: "192.168.1.10",
            roomName: "Living Room",
            discoveryIDs: [discoveryAlias],
            capabilities: [
                .directionalNavigation,
                .power
            ]
        )

        store.addOrUpdate(manuallyResolved)

        let firstDiscovery = TVDevice(
            id: discoveryAlias,
            name: "Samsung TV",
            platform: .samsung,
            host: "192.168.1.10",
            port: 8002
        )

        let firstChanges = store.refreshKnownDevices(
            from: [firstDiscovery]
        )

        XCTAssertTrue(firstChanges.isEmpty)
        XCTAssertEqual(
            store.devices.count,
            1
        )
        XCTAssertEqual(
            store.selectedDevice?.id,
            manuallyResolved.id
        )
        XCTAssertTrue(
            store.selectedDevice?
                .discoveryAliases
                .contains(
                    firstDiscovery.id
                ) == true
        )
        XCTAssertEqual(
            store.selectedDevice?.port,
            8002
        )
        XCTAssertEqual(
            store.selectedDevice?.name,
            "Living Room"
        )

        let movedDiscovery = TVDevice(
            id: firstDiscovery.id,
            name: "Samsung TV",
            platform: .samsung,
            host: "192.168.1.44",
            port: 8002
        )

        let secondChanges = store.refreshKnownDevices(
            from: [movedDiscovery]
        )

        XCTAssertEqual(
            secondChanges,
            [manuallyResolved.id]
        )
        XCTAssertEqual(
            store.selectedDevice?.host,
            "192.168.1.44"
        )
        XCTAssertEqual(
            store.selectedDevice?.roomName,
            "Living Room"
        )
    }

    func testAddOrUpdateUsesSavedIdentityForDiscoveryAlias() {
        clearDeviceDefaults()
        defer { clearDeviceDefaults() }

        let store = DeviceStore()

        let saved = TVDevice(
            id: "lg-hardware-1",
            name: "Bedroom",
            platform: .lgWebOS,
            host: "192.168.1.12",
            discoveryID: "lg-uuid:ssdp-1"
        )

        store.addOrUpdate(saved)

        let rediscovered = TVDevice(
            id: "lg-uuid:ssdp-1",
            name: "LG TV",
            platform: .lgWebOS,
            host: "192.168.1.55",
            port: 3001
        )

        let stored = store.addOrUpdate(
            rediscovered
        )

        XCTAssertEqual(
            store.devices.count,
            1
        )
        XCTAssertEqual(
            stored.id,
            saved.id
        )
        XCTAssertEqual(
            stored.host,
            "192.168.1.55"
        )
        XCTAssertEqual(
            store.selectedDeviceID,
            saved.id
        )
    }

    func testDifferentTVAtReusedHostDoesNotMerge() {
        clearDeviceDefaults()
        defer { clearDeviceDefaults() }

        let store = DeviceStore()

        let first = TVDevice(
            id: "samsung-runtime-a",
            name: "Old TV",
            platform: .samsung,
            host: "192.168.1.24",
            discoveryIDs: [
                "samsung-uuid-a"
            ]
        )
        store.addOrUpdate(first)

        let replacement = TVDevice(
            id: "samsung-uuid-b",
            name: "Samsung TV",
            platform: .samsung,
            host: "192.168.1.24",
            port: 8002
        )

        let changes = store.refreshKnownDevices(
            from: [replacement]
        )

        XCTAssertTrue(changes.isEmpty)
        XCTAssertEqual(
            store.devices.count,
            1
        )
        XCTAssertEqual(
            store.devices.first?.id,
            first.id
        )
        XCTAssertFalse(
            store.devices.first?
                .discoveryAliases
                .contains(
                    replacement.id
                ) == true
        )
    }

    func testNonDefaultLearnedPortCountsAsEndpointMovement() {
        clearDeviceDefaults()
        defer { clearDeviceDefaults() }

        let store = DeviceStore()
        let alias = "samsung-uuid-port"

        let saved = TVDevice(
            id: "samsung-runtime-port",
            name: "Samsung TV",
            platform: .samsung,
            host: "192.168.1.30",
            discoveryIDs: [alias]
        )
        store.addOrUpdate(saved)

        let discovered = TVDevice(
            id: alias,
            name: "Samsung TV",
            platform: .samsung,
            host: "192.168.1.30",
            port: 9000
        )

        let changes = store.refreshKnownDevices(
            from: [discovered]
        )

        XCTAssertEqual(
            changes,
            [saved.id]
        )
        XCTAssertEqual(
            store.selectedDevice?.port,
            9000
        )
    }

    func testDiscoveryAliasesAccumulateWithoutOverwrite() {
        clearDeviceDefaults()
        defer { clearDeviceDefaults() }

        let store = DeviceStore()

        let saved = TVDevice(
            id: "lg-runtime-1",
            name: "LG TV",
            platform: .lgWebOS,
            host: "192.168.1.40",
            discoveryIDs: [
                "lg-uuid-a",
                "lg-uuid-b"
            ]
        )
        store.addOrUpdate(saved)

        let rediscovered = TVDevice(
            id: "lg-uuid-b",
            name: "LG TV",
            platform: .lgWebOS,
            host: "192.168.1.41",
            port: 3001,
            discoveryIDs: [
                "lg-uuid-c"
            ]
        )

        _ = store.addOrUpdate(
            rediscovered
        )

        XCTAssertEqual(
            store.devices.count,
            1
        )
        XCTAssertEqual(
            store.selectedDevice?
                .discoveryAliases,
            [
                "lg-uuid-a",
                "lg-uuid-b",
                "lg-uuid-c"
            ]
        )
    }

    func testRoomNameCanBeAssignedAndCleared() {
        clearDeviceDefaults()
        defer { clearDeviceDefaults() }

        let store = DeviceStore()
        let device = TVDevice(
            id: "room-tv",
            name: "TV",
            platform: .samsung,
            host: "192.168.1.60"
        )

        store.addOrUpdate(device)
        store.setRoomName(
            for: device.id,
            to: " Living Room "
        )

        XCTAssertEqual(
            store.selectedDevice?.roomName,
            "Living Room"
        )

        store.setRoomName(
            for: device.id,
            to: "   "
        )

        XCTAssertNil(
            store.selectedDevice?.roomName
        )
    }

    func testStoredIdentityMatchesDiscoveryAliasButNotAnotherTV() {
        clearDeviceDefaults()
        defer { clearDeviceDefaults() }

        let store = DeviceStore()
        let saved = TVDevice(
            id: "samsung-runtime-free",
            name: "Living Room",
            platform: .samsung,
            host: "192.168.1.21",
            discoveryIDs: [
                "samsung-uuid-free"
            ]
        )
        store.addOrUpdate(saved)

        let sameTV = TVDevice(
            id: "samsung-uuid-free",
            name: "Samsung TV",
            platform: .samsung,
            host: "192.168.1.88"
        )
        let otherTV = TVDevice(
            id: "samsung-uuid-other",
            name: "Samsung TV",
            platform: .samsung,
            host: "192.168.1.21"
        )

        XCTAssertTrue(
            store.matchesStoredDevice(
                sameTV,
                id: saved.id
            )
        )
        XCTAssertFalse(
            store.matchesStoredDevice(
                otherTV,
                id: saved.id
            )
        )
    }

    func testAndroidProvisionalIPAliasDoesNotMatchStableTV() {
        clearDeviceDefaults()
        defer { clearDeviceDefaults() }

        let store = DeviceStore()
        let stableID =
            "androidtv-0123456789abcdef0123456789abcdef"

        let saved = TVDevice(
            id: stableID,
            name: "Google TV",
            platform: .androidTV,
            host: "192.168.1.20",
            discoveryIDs: [
                "androidtv-192.168.1.20"
            ]
        )
        store.addOrUpdate(saved)

        let replacementAtReusedIP = TVDevice(
            id: "androidtv-192.168.1.20",
            name: "Android TV",
            platform: .androidTV,
            host: "192.168.1.20"
        )

        XCTAssertFalse(
            store.matchesStoredDevice(
                replacementAtReusedIP,
                id: stableID
            )
        )
    }

    func testAndroidBonjourNameIsNotAStableAlias() {
        clearDeviceDefaults()
        defer { clearDeviceDefaults() }

        let store = DeviceStore()
        let stableID =
            "androidtv-fedcba9876543210fedcba9876543210"

        let saved = TVDevice(
            id: stableID,
            name: "Living Room",
            platform: .androidTV,
            host: "192.168.1.30",
            discoveryIDs: [
                "androidtv-google tv streamer"
            ]
        )
        store.addOrUpdate(saved)

        let anotherStreamer = TVDevice(
            id: "androidtv-google tv streamer",
            name: "Google TV Streamer",
            platform: .androidTV,
            host: "192.168.1.31"
        )

        XCTAssertFalse(
            store.matchesStoredDevice(
                anotherStreamer,
                id: stableID
            )
        )
    }

    func testRemovingFreeDevicePromotesNextSavedTV() {
        clearDeviceDefaults()
        defer { clearDeviceDefaults() }

        let store = DeviceStore()

        let first = TVDevice(
            id: "first",
            name: "First TV",
            platform: .samsung,
            host: "192.168.1.10"
        )
        let second = TVDevice(
            id: "second",
            name: "Second TV",
            platform: .lgWebOS,
            host: "192.168.1.11"
        )

        store.addOrUpdate(first)
        store.addOrUpdate(second)
        store.select(first)

        UserDefaults.standard.set(
            first.id,
            forKey: AppSettings.Keys.freeDeviceID
        )

        store.remove(first)

        XCTAssertEqual(
            store.selectedDeviceID,
            second.id
        )
        XCTAssertEqual(
            UserDefaults.standard.string(
                forKey: AppSettings.Keys.freeDeviceID
            ),
            second.id
        )
    }

    private func clearDeviceDefaults() {
        for key in [
            AppSettings.Keys.savedDevices,
            AppSettings.Keys.selectedDeviceID,
            AppSettings.Keys.freeDeviceID
        ] {
            UserDefaults.standard.removeObject(
                forKey: key
            )
        }
    }
}

final class TVControlErrorTests: XCTestCase {
    func testOnlyTransportFailuresInvalidateConnection() {
        XCTAssertTrue(
            TVControlError.unreachable
                .affectsConnectionState
        )
        XCTAssertTrue(
            TVControlError.transport("lost")
                .affectsConnectionState
        )

        XCTAssertFalse(
            TVControlError.unsupported
                .affectsConnectionState
        )
        XCTAssertFalse(
            TVControlError.permissionDenied("denied")
                .affectsConnectionState
        )
        XCTAssertFalse(
            TVControlError.rejected(
                status: 400,
                message: nil
            )
            .affectsConnectionState
        )
        XCTAssertFalse(
            TVControlError.invalidResponse
                .affectsConnectionState
        )
    }
}

@MainActor
final class RemoteFavoritesStoreTests: XCTestCase {
    func testFavoritesMigrateAcrossResolvedDeviceIdentity() {
        UserDefaults.standard.removeObject(
            forKey: AppSettings.Keys.remoteFavorites
        )
        defer {
            UserDefaults.standard.removeObject(
                forKey: AppSettings.Keys.remoteFavorites
            )
        }

        let store = RemoteFavoritesStore()

        store.toggle(
            deviceID: "temporary",
            favorite: RemoteFavorite(
                kind: .input,
                targetID: "hdmi1",
                name: "HDMI 1"
            )
        )

        store.migrate(
            from: "temporary",
            to: "stable"
        )

        XCTAssertTrue(
            store.contains(
                deviceID: "stable",
                kind: .input,
                targetID: "hdmi1"
            )
        )
        XCTAssertFalse(
            store.contains(
                deviceID: "temporary",
                kind: .input,
                targetID: "hdmi1"
            )
        )
    }
}


@MainActor
final class TVAdapterEventEmitterTests: XCTestCase {
    func testFreshSubscriptionReceivesEventsAfterPreviousCancellation() async {
        let emitter = TVAdapterEventEmitter()

        let firstStream = emitter.stream
        let firstTask = Task {
            for await _ in firstStream {
                // The first monitor intentionally has no work.
            }
        }

        firstTask.cancel()
        _ = await firstTask.result

        let received =
            expectation(
                description:
                    "fresh event stream receives event"
            )
        var capturedEvent: TVAdapterEvent?

        let secondStream = emitter.stream
        let receiveTask = Task { @MainActor in
            for await event in secondStream {
                capturedEvent = event
                received.fulfill()
                return
            }
        }

        await Task.yield()

        emitter.yield(
            .disconnected(
                message: "second connection"
            )
        )

        await fulfillment(
            of: [received],
            timeout: 1.0
        )
        receiveTask.cancel()

        XCTAssertEqual(
            capturedEvent,
            .disconnected(
                message: "second connection"
            )
        )
    }
}

@MainActor
final class RemoteCommandQueueTests: XCTestCase {
    func testRepeatIsCoalescedButDiscreteCommandIsPreserved() async {
        let queue = RemoteCommandQueue()
        var delivered: [RemoteCommand] = []

        let firstRepeat = queue.enqueue(
            command: .up,
            coalescing: true
        ) {
            delivered.append(.up)
        }

        let duplicateRepeat = queue.enqueue(
            command: .up,
            coalescing: true
        ) {
            delivered.append(.up)
        }

        let discrete = queue.enqueue(
            command: .home,
            coalescing: false
        ) {
            delivered.append(.home)
        }

        XCTAssertTrue(firstRepeat)
        XCTAssertFalse(duplicateRepeat)
        XCTAssertTrue(discrete)

        await queue.waitUntilIdle()

        XCTAssertEqual(
            delivered,
            [.up, .home]
        )
    }

    func testCancelPreventsQueuedGenerationFromRunning() async {
        let queue = RemoteCommandQueue()
        var delivered: [RemoteCommand] = []

        _ = queue.enqueue(
            command: .left,
            coalescing: true
        ) {
            delivered.append(.left)
        }

        queue.cancel()
        await queue.waitUntilIdle()

        XCTAssertTrue(
            delivered.isEmpty
        )
    }
}
