// Copyright 2025–2026 Skip
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

    func testDeviceIdentityValueConstructionTrimsEmptyStrings() {
        let identity = DeviceIdentity(
            name: "  Pixel  ",
            model: "  ",
            systemName: "Android",
            manufacturer: "Google"
        )

        XCTAssertEqual(identity.name, "Pixel")
        XCTAssertNil(identity.model)
        XCTAssertEqual(identity.systemName, "Android")
        XCTAssertEqual(identity.manufacturer, "Google")
    }

    func testDeviceIdentityCurrentHasPlatformName() {
        let identity = DeviceIdentity.current

        XCTAssertNotNil(identity.systemName)
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

        provider.publishLifecycle(ApplicationLifecycleEventKind.didEnterBackground)

        let event = await iterator.next()
        XCTAssertEqual(event?.kind, ApplicationLifecycleEventKind.didEnterBackground)
        XCTAssertEqual(event?.phase, ApplicationLifecyclePhase.background)
        provider.stop()
    }

    func testApplicationLifecycleEventPhaseInitializerSetsMatchingKind() {
        let event = ApplicationLifecycleEvent(phase: ApplicationLifecyclePhase.active)

        XCTAssertEqual(event.kind, ApplicationLifecycleEventKind.didBecomeActive)
        XCTAssertEqual(event.phase, ApplicationLifecyclePhase.active)
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

    #if SKIP
    // SKIP INSERT: @org.robolectric.annotation.Config(sdk = [28])
    func testMonitorDeliversFixesBelowAPI31() async throws {
        try await assertMonitorDeliversSimulatedFix(from: android.location.LocationManager.GPS_PROVIDER)
    }

    // SKIP INSERT: @org.robolectric.annotation.Config(sdk = [33])
    func testMonitorDeliversFixesFromAPI31() async throws {
        try await assertMonitorDeliversSimulatedFix(from: android.location.LocationManager.FUSED_PROVIDER)
    }

    @MainActor private func assertMonitorDeliversSimulatedFix(from provider: String) async throws {
        let application = ProcessInfo.processInfo.androidContext as android.app.Application
        org.robolectric.Shadows.shadowOf(application).grantPermissions(android.Manifest.permission.ACCESS_FINE_LOCATION, android.Manifest.permission.ACCESS_COARSE_LOCATION)
        let locationManager = application.getSystemService(android.content.Context.LOCATION_SERVICE) as android.location.LocationManager
        let shadowLocationManager = org.robolectric.Shadows.shadowOf(locationManager)
        shadowLocationManager.setProviderEnabled(provider, true)

        let locationProvider = LocationProvider()
        let stream = locationProvider.monitor(quality: LocationQuality.navigation)

        let fix = android.location.Location(provider)
        fix.setLatitude(51.5072)
        fix.setLongitude(-0.1276)
        fix.setAccuracy(Float(5.0))
        fix.setTime(java.lang.System.currentTimeMillis())
        fix.setElapsedRealtimeNanos(android.os.SystemClock.elapsedRealtimeNanos())
        shadowLocationManager.simulateLocation(fix)
        org.robolectric.Shadows.shadowOf(android.os.Looper.getMainLooper()).idle()

        var received: LocationEvent? = nil
        for try await event in stream {
            received = event
            break
        }
        locationProvider.stop()

        XCTAssertEqual(51.5072, received?.latitude ?? 0.0, accuracy: 0.0001)
        XCTAssertEqual(-0.1276, received?.longitude ?? 0.0, accuracy: 0.0001)
    }
    #endif
}
