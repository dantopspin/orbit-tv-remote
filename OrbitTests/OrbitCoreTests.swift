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
