// Copyright 2025–2026 Skip
// SPDX-License-Identifier: MPL-2.0
import XCTest
import OSLog
import Foundation
@testable import SkipDevice

let logger: Logger = Logger(subsystem: "SkipDevice", category: "Tests")

@available(macOS 13, macCatalyst 16, iOS 16, tvOS 16, watchOS 8, *)
final class SkipDeviceTests: XCTestCase {
    func testNetworkReachability() async throws {
        let isReachable = NetworkReachability.isNetworkReachable
        XCTAssertTrue(isReachable, "expected the network to be reachable")
    }

    func testBackgroundActivityRequestDefaults() {
        let request = BackgroundActivityRequest(name: "Sync")
        XCTAssertEqual(request.name, "Sync")
        XCTAssertEqual(request.reason, BackgroundActivityReason.shortCriticalWork)
        XCTAssertEqual(request.detail, "")
        XCTAssertEqual(request.notificationChannelID, "tools.skip.device.background_activity")
        XCTAssertEqual(request.notificationID, 41_001)
        XCTAssertEqual(request.notificationIconResourceName, "ic_notification")
    }

    func testBackgroundActivityRequestCustomValues() {
        let request = BackgroundActivityRequest(
            name: "Proxy media",
            reason: BackgroundActivityReason.localNetworkTransfer,
            detail: "Streaming to a receiver",
            notificationChannelID: "custom.channel",
            notificationID: 7,
            notificationIconResourceName: "custom_icon"
        )
        XCTAssertEqual(request.name, "Proxy media")
        XCTAssertEqual(request.reason, BackgroundActivityReason.localNetworkTransfer)
        XCTAssertEqual(request.detail, "Streaming to a receiver")
        XCTAssertEqual(request.notificationChannelID, "custom.channel")
        XCTAssertEqual(request.notificationID, 7)
        XCTAssertEqual(request.notificationIconResourceName, "custom_icon")
    }

    func testApplicationRuntimeProviderPublishesLifecycleEvents() async {
        let provider = ApplicationRuntimeProvider()
        var iterator = provider.monitorLifecycle().makeAsyncIterator()
        _ = await iterator.next()

        provider.publishLifecycle(ApplicationLifecyclePhase.background)

        let event = await iterator.next()
        XCTAssertEqual(event?.phase, ApplicationLifecyclePhase.background)
        provider.stop()
    }

    func testApplicationRuntimeProviderPublishesMemoryPressureEvents() async {
        let provider = ApplicationRuntimeProvider()
        var iterator = provider.monitorMemoryPressure().makeAsyncIterator()

        provider.publishMemoryPressure(MemoryPressureLevel.critical)

        let event = await iterator.next()
        XCTAssertEqual(event?.level, MemoryPressureLevel.critical)
        provider.stop()
    }

    #if SKIP
    func testBackgroundActivityReasonServiceTypeMapping() {
        XCTAssertEqual(BackgroundActivity.serviceType(for: BackgroundActivityReason.localNetworkTransfer), android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        XCTAssertEqual(BackgroundActivity.serviceType(for: BackgroundActivityReason.connectedDeviceTransfer), android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        if android.os.Build.VERSION.SDK_INT >= 35 {
            XCTAssertEqual(BackgroundActivity.serviceType(for: BackgroundActivityReason.mediaProcessing), android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROCESSING)
        } else {
            XCTAssertEqual(BackgroundActivity.serviceType(for: BackgroundActivityReason.mediaProcessing), android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        }
        if android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.UPSIDE_DOWN_CAKE {
            XCTAssertEqual(BackgroundActivity.serviceType(for: BackgroundActivityReason.shortCriticalWork), android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SHORT_SERVICE)
        } else {
            XCTAssertEqual(BackgroundActivity.serviceType(for: BackgroundActivityReason.shortCriticalWork), android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        }
    }
    #endif

    func testLocationProvier() async throws {
        let lp = LocationProvider()

        throw XCTSkip("Skipping fetchCurrentLocation due to hang")

        let location = try await lp.fetchCurrentLocation()
        XCTAssertNotEqual(0.0, location.latitude)
    }
}
