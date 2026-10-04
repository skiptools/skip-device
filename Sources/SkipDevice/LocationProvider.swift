// Copyright 2025–2026 Skip
// SPDX-License-Identifier: MPL-2.0
#if !SKIP_BRIDGE
import Foundation
#if canImport(OSLog)
import OSLog
#endif
#if !SKIP
import CoreLocation
#else
import android.os.Looper
import android.content.Context
import android.location.LocationManager
import android.location.LocationRequest
import android.location.LocationListener
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume

typealias NSObject = AnyObject
#endif

private let logger: Logger = Logger(subsystem: "skip.device", category: "LocationProvider") // adb logcat '*:S' 'skip.device.LocationProvider:V'

/// A current location fetcher.
///
/// Requires `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` in `App.xcconfig` and
/// `<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>` in `AndroidManifest.xml`.
public final class LocationProvider: NSObject, @unchecked Sendable {
    #if SKIP
    private let locationManager = ProcessInfo.processInfo.androidContext.getSystemService(Context.LOCATION_SERVICE) as LocationManager
    private var listener: LocListener?
    #else
    private var locationManager: CLLocationManager?
    private var monitorContinuation: AsyncThrowingStream<LocationEvent, Error>.Continuation?
    private var pendingFetchContinuations: [UUID: CheckedContinuation<LocationEvent, Error>] = [:]
    private var isFetchingCurrentLocation = false
    #endif

    // SKIP @nooverride
    public override init() {
        super.init()
    }

    deinit {
        #if SKIP
        stop()
        #else
        locationManager?.delegate = nil
        locationManager?.stopUpdatingLocation()
        #endif
    }

    /// Returns `true` if the location is available on this device
    public var isAvailable: Bool {
        #if SKIP
        return locationManager.isProviderEnabled(LocationManager.FUSED_PROVIDER) || locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER) || locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
        #else
        return CLLocationManager.locationServicesEnabled()
        #endif
    }

    public func stop() {
        #if SKIP
        if listener != nil {
            locationManager.removeUpdates(listener!)
            listener = nil
        }
        #else
        Task { @MainActor [weak self] in
            self?.stopMonitoring()
        }
        #endif
    }

    public func monitor() -> AsyncThrowingStream<LocationEvent, Error> {
        logger.debug("starting location monitor")
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: LocationEvent.self)

        #if SKIP
        listener = LocListener(callback: { location in
            logger.info("location update: \(location.latitude) \(location.longitude)")
            continuation.yield(with: .success(location))
        })
        let intervalMillis = Int64(1_000)
        // https://developer.android.com/reference/android/location/LocationRequest.Builder
        let request = LocationRequest.Builder(intervalMillis).build() // TODO: setQuality, etc.
        do {
            locationManager.requestLocationUpdates(LocationManager.FUSED_PROVIDER, request, ProcessInfo.processInfo.androidContext.mainExecutor, listener!)
        } catch {
            logger.error("error requesting location updates: \(error) ")
            continuation.yield(with: .failure(error))
        }
        #else
        Task { @MainActor [weak self] in
            guard let self else {
                continuation.finish()
                return
            }

            let manager = self.configuredLocationManager()
            self.monitorContinuation = continuation
            manager.startUpdatingLocation()
        }
        #endif

        continuation.onTermination = { [weak self] _ in
            logger.debug("cancelling location monitor")
            self?.stop()
        }

        return stream
    }

    /// Issues a single-shot request for the current location
    public func fetchCurrentLocation() async throws -> LocationEvent {
        logger.info("fetchCurrentLocation")
        #if !SKIP
        @MainActor
        func requestCurrentLocation() async throws -> LocationEvent {
            guard CLLocationManager.locationServicesEnabled() else {
                throw LocationError(errorDescription: "Location services are disabled")
            }

            let manager = configuredLocationManager()
            if let location = manager.location {
                logger.info("using last known location")
                return LocationEvent(location: location)
            }

            let requestID = UUID()
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    pendingFetchContinuations[requestID] = continuation
                    manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters

                    if !isFetchingCurrentLocation {
                        isFetchingCurrentLocation = true
                        manager.requestLocation()
                    }
                }
            } onCancel: { [weak self] in
                Task { @MainActor in
                    self?.cancelPendingFetch(id: requestID)
                }
            }
        }

        return try await requestCurrentLocation()
        #else
        let context = ProcessInfo.processInfo.androidContext
        let locationManager = context.getSystemService(Context.LOCATION_SERVICE) as android.location.LocationManager
        let providers = [
            android.location.LocationManager.FUSED_PROVIDER,
            android.location.LocationManager.GPS_PROVIDER,
            android.location.LocationManager.NETWORK_PROVIDER,
        ]

        var newestCachedLocation: android.location.Location?
        for provider in providers {
            guard let location = locationManager.getLastKnownLocation(provider) else {
                continue
            }

            if let newest = newestCachedLocation {
                if location.getElapsedRealtimeNanos() > newest.getElapsedRealtimeNanos() {
                    newestCachedLocation = location
                }
            } else {
                newestCachedLocation = location
            }
        }

        if let newestCachedLocation {
            logger.info("using newest last known location")
            return LocationEvent(location: newestCachedLocation)
        }

        let locationListener = LocListener()
        let location = suspendCancellableCoroutine { continuation in
            locationListener.callback = {
                locationManager.removeUpdates(locationListener)
                continuation.resume($0)
            }

            continuation.invokeOnCancellation { _ in
                locationManager.removeUpdates(locationListener)
                continuation.cancel()
            }

            logger.info("locationManager.requestSingleUpdate")
            locationManager.requestSingleUpdate(android.location.LocationManager.FUSED_PROVIDER, locationListener, Looper.getMainLooper())
        }
        let _ = locationListener // need to hold the reference so it doesn't get gc'd
        return location
        #endif
    }

    #if !SKIP
    @MainActor
    private func configuredLocationManager() -> CLLocationManager {
        if let locationManager {
            locationManager.delegate = self
            return locationManager
        }

        let locationManager = CLLocationManager()
        locationManager.delegate = self
        self.locationManager = locationManager
        return locationManager
    }

    @MainActor
    private func stopMonitoring() {
        locationManager?.stopUpdatingLocation()
        monitorContinuation = nil
    }

    @MainActor
    private func cancelPendingFetch(id: UUID) {
        guard let continuation = pendingFetchContinuations.removeValue(forKey: id) else {
            return
        }

        continuation.resume(throwing: CancellationError())
        if pendingFetchContinuations.isEmpty {
            isFetchingCurrentLocation = false
        }
    }

    @MainActor
    private func completePendingFetches(with result: Result<LocationEvent, Error>) {
        guard !pendingFetchContinuations.isEmpty else {
            isFetchingCurrentLocation = false
            return
        }

        let continuations = pendingFetchContinuations.values
        pendingFetchContinuations.removeAll()
        isFetchingCurrentLocation = false

        for continuation in continuations {
            switch result {
            case .success(let location):
                continuation.resume(returning: location)
            case .failure(let error):
                continuation.resume(throwing: error)
            }
        }
    }
    #endif
}

#if SKIP
class LocListener : LocationListener {
    var callback: (LocationEvent) -> Void = { _ in }

    init() {}

    init(callback: @escaping (LocationEvent) -> Void) {
        self.callback = callback
    }

    override func onLocationChanged(location: android.location.Location) {
        callback(LocationEvent(location: location))
    }

    override func onStatusChanged(provider: String?, status: Int, extras: android.os.Bundle?) {}
    //override func onProviderEnabled(provider: String?) {}
    //override func onProviderDisabled(provider: String?) {}
}
#else
extension LocationProvider: CLLocationManagerDelegate {
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated {
            logger.info("LocationProvider.didUpdateLocations: \(locations)")

            for location in locations {
                monitorContinuation?.yield(with: .success(LocationEvent(location: location)))
            }

            if let location = locations.last {
                completePendingFetches(with: .success(LocationEvent(location: location)))
            }
        }
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            logger.error("LocationProvider.didFailWithError: \(error)")
            monitorContinuation?.yield(with: .failure(error))
            monitorContinuation = nil
            completePendingFetches(with: .failure(error))
        }
    }

    public func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: any Error) {
        MainActor.assumeIsolated {
            logger.error("LocationProvider.monitoringDidFailFor: \(error)")
            monitorContinuation?.yield(with: .failure(error))
            monitorContinuation = nil
            completePendingFetches(with: .failure(error))
        }
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        logger.info("LocationProvider.locationManagerDidChangeAuthorization: \(manager.authorizationStatus.rawValue)")
    }
}
#endif

public struct LocationError : LocalizedError {
    public var errorDescription: String?
}

/// A lat/lon location (in degrees).
public struct LocationEvent: Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public var horizontalAccuracy: Double

    public var altitude: Double
    public var ellipsoidalAltitude: Double
    public var verticalAccuracy: Double

    public var speed: Double
    public var speedAccuracy: Double

    public var course: Double
    public var courseAccuracy: Double

    public var timestamp: TimeInterval

    #if SKIP
    /// https://developer.android.com/reference/android/location/Location
    init(location: android.location.Location) {
        self.latitude = location.getLatitude()
        self.longitude = location.getLongitude()
        // some accessors may fail with precondition exceptions like `java.lang.IllegalStateException: The Mean Sea Level altitude of this location is not set.`, so we defensively check whether the property is set and fallback to empty values
        self.horizontalAccuracy = location.hasAccuracy() ? location.getAccuracy().toDouble() : 0.0
        // https://developer.android.com/reference/android/location/Location#getMslAltitudeMeters()
        // `hasMslAltitude()`/`getMslAltitudeMeters()` were added in API 34 (Android 14); calling them on older devices throws NoSuchMethodError
        if android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.UPSIDE_DOWN_CAKE, location.hasMslAltitude() {
            self.altitude = location.getMslAltitudeMeters()
        } else {
            self.altitude = 0.0
        }
        self.ellipsoidalAltitude = location.hasAltitude() ? location.getAltitude() : 0.0
        self.verticalAccuracy = location.hasVerticalAccuracy() ? location.getVerticalAccuracyMeters().toDouble() : 0.0
        self.speed = location.hasSpeed() ? location.getSpeed().toDouble() : 0.0
        self.speedAccuracy = location.hasSpeedAccuracy() ? location.getSpeedAccuracyMetersPerSecond().toDouble() : 0.0
        self.course = location.hasBearing() ? location.getBearing().toDouble() : 0.0
        self.courseAccuracy = location.hasBearingAccuracy() ? location.getBearingAccuracyDegrees().toDouble() : 0.0
        self.timestamp = location.getTime().toDouble() / 1_000.0
    }
    #else
    /// https://developer.apple.com/documentation/corelocation/cllocation
    init(location: CLLocation) {
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.horizontalAccuracy = location.horizontalAccuracy
        self.altitude = location.altitude
        self.ellipsoidalAltitude = location.ellipsoidalAltitude
        self.verticalAccuracy = location.verticalAccuracy
        self.speed = location.speed
        self.speedAccuracy = location.speedAccuracy
        self.course = location.course
        self.courseAccuracy = location.courseAccuracy
        self.timestamp = location.timestamp.timeIntervalSince1970
    }
    #endif
}
#endif
