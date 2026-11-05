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

    func testGeocodedPlaceNormalizesBlankFields() {
        let place = GeocodedPlace(latitude: 12.9352, longitude: 77.6245, name: "  ", locality: " Bengaluru ", country: "")

        XCTAssertNil(place.name)
        XCTAssertEqual(place.locality, "Bengaluru")
        XCTAssertNil(place.country)
        XCTAssertNil(place.postalCode)
    }

    func testGeocodedPlaceJoinedSkipsBlankAndRepeatedParts() {
        let parts: [String?] = ["Koramangala", nil, " ", "Koramangala", "Bengaluru"]
        XCTAssertEqual(parts.joinedNonEmpty, "Koramangala, Bengaluru")
        let blank: [String?] = [nil, ""]
        XCTAssertNil(blank.joinedNonEmpty)
    }

    func testGeocodeBlankQueryReturnsNoResults() async throws {
        let provider = GeocodingProvider()
        let places = try await provider.geocode(address: "   ")
        XCTAssertEqual(places.count, 0)
        let none = try await provider.geocode(address: "Bengaluru", maxResults: 0)
        XCTAssertEqual(none.count, 0)
    }

    #if SKIP
    func testGeocodedPlaceFromAndroidAddress() {
        let address = android.location.Address(java.util.Locale.US)
        address.setLatitude(37.3349)
        address.setLongitude(-122.009)
        address.setFeatureName("Apple Park")
        address.setAddressLine(0, "1 Apple Park Way")
        address.setAddressLine(1, "Cupertino, CA 95014")
        address.setSubLocality("")
        address.setLocality("Cupertino")
        address.setAdminArea("California")
        address.setPostalCode("95014")
        address.setCountryName("United States")
        address.setCountryCode("US")

        let place = GeocodedPlace(address: address)
        XCTAssertEqual(place.latitude, 37.3349)
        XCTAssertEqual(place.longitude, -122.009)
        XCTAssertEqual(place.name, "Apple Park")
        XCTAssertEqual(place.formattedAddress, "1 Apple Park Way, Cupertino, CA 95014")
        XCTAssertNil(place.subLocality)
        XCTAssertEqual(place.locality, "Cupertino")
        XCTAssertEqual(place.administrativeArea, "California")
        XCTAssertEqual(place.postalCode, "95014")
        XCTAssertEqual(place.country, "United States")
        XCTAssertEqual(place.countryCode, "US")
    }
    #endif

    func testGeocodingProviderLiveLookup() async throws {
        // Live geocoding needs the network and a platform geocoder, and is rate-limited,
        // so it only runs when explicitly requested.
        if ProcessInfo.processInfo.environment["SKIP_DEVICE_LIVE_GEOCODING"] == nil {
            throw XCTSkip("Set SKIP_DEVICE_LIVE_GEOCODING=1 to run live geocoding lookups")
        }
        let provider = GeocodingProvider(locale: Locale(identifier: "en_US"))
        if !provider.isAvailable {
            throw XCTSkip("No geocoder available on this device")
        }

        let places = try await provider.geocode(address: "Cupertino, CA")
        let place = try XCTUnwrap(places.first)
        XCTAssertEqual(place.latitude, 37.32, accuracy: 0.1)
        XCTAssertEqual(place.longitude, -122.03, accuracy: 0.1)

        let reverse = try await provider.reverseGeocode(latitude: place.latitude, longitude: place.longitude)
        XCTAssertEqual(reverse.first?.locality, "Cupertino")
    }

    func testLocationProvier() async throws {
        let lp = LocationProvider()

        throw XCTSkip("Skipping fetchCurrentLocation due to hang")

        let location = try await lp.fetchCurrentLocation()
        XCTAssertNotEqual(0.0, location.latitude)
    }
}
