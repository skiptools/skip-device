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

/// The desired quality of location updates, trading power consumption against accuracy.
///
/// Maps onto [`LocationRequest.QUALITY_*`](https://developer.android.com/reference/android/location/LocationRequest)
/// on Android and `CLLocationManager.desiredAccuracy` on Darwin. The two platforms have
/// different out-of-the-box defaults — Android's `LocationRequest` defaults to
/// `QUALITY_BALANCED_POWER_ACCURACY` while `CLLocationManager` defaults to
/// `kCLLocationAccuracyBest` — so `platformDefault` leaves each side untouched rather
/// than trying to unify them.
public enum LocationQuality: Int, Hashable, Sendable {
    /// Leave the platform's own default in place (the behaviour before this parameter existed).
    case platformDefault = 0
    /// Prefer power savings over accuracy; fixes are typically resolved from cell/wifi.
    case lowPower = 1
    /// Balance power against accuracy.
    case balanced = 2
    /// Prefer accuracy over power, requesting GNSS where it is available.
    case highAccuracy = 3
    /// The highest available accuracy, tuned for turn-by-turn navigation.
    case navigation = 4

    #if SKIP
    /// The `LocationRequest.QUALITY_*` constant to request, or `nil` to leave the builder's default.
    var androidQuality: Int? {
        switch self {
        case .platformDefault: return nil
        case .lowPower: return LocationRequest.QUALITY_LOW_POWER
        case .balanced: return LocationRequest.QUALITY_BALANCED_POWER_ACCURACY
        // Android has no separate navigation tier; `QUALITY_HIGH_ACCURACY` is the top of the scale.
        case .highAccuracy, .navigation: return LocationRequest.QUALITY_HIGH_ACCURACY
        }
    }
    #else
    /// The `CLLocationManager.desiredAccuracy` to set, or `nil` to leave CoreLocation's default.
    var desiredAccuracy: CLLocationAccuracy? {
        switch self {
        case .platformDefault: return nil
        case .lowPower: return kCLLocationAccuracyHundredMeters
        case .balanced: return kCLLocationAccuracyNearestTenMeters
        case .highAccuracy: return kCLLocationAccuracyBest
        case .navigation: return kCLLocationAccuracyBestForNavigation
        }
    }
    #endif
}

/// A current location fetcher.
///
/// Requires `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` in `App.xcconfig` and
/// `<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>` in `AndroidManifest.xml`.
public final class LocationProvider: NSObject, @unchecked Sendable {
    #if SKIP
    private let locationManager = ProcessInfo.processInfo.androidContext.getSystemService(Context.LOCATION_SERVICE) as LocationManager
    private var listener: LocListener?
    #else
    private let locationManager = CLLocationManager()
    private var callback: ((Result<LocationEvent, Error>) -> Void)?
    #endif

    // SKIP @nooverride
    public override init() {
        super.init()
        #if !SKIP
        locationManager.delegate = self
        #endif
    }

    deinit {
        stop()
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
        locationManager.stopUpdatingLocation()
        #endif
    }

    /// Begins monitoring the device location, yielding a ``LocationEvent`` per fix.
    ///
    /// - Parameters:
    ///   - quality: the accuracy/power trade-off to request. Defaults to
    ///     ``LocationQuality/platformDefault``, which leaves each platform's own default in place.
    ///   - interval: the *desired* interval between fixes, defaulting to one second. This is a
    ///     request, not a guarantee — the platform may deliver less often, and at
    ///     ``LocationQuality/balanced`` it demonstrably does. `quality` is the lever that
    ///     changes that; `interval` alone will not.
    ///   - minimumInterval: the fastest rate at which the caller can accept fixes — Android will
    ///     not deliver two updates closer together than this. Note this bounds delivery from the
    ///     *fast* side only: it is a rate limiter, and does not stop the platform delivering more
    ///     slowly than `interval`. Pass `0` (the default) to leave the platform's own default (a
    ///     sixth of `interval`) in place. Ignored on Darwin, which has no equivalent knob.
    public func monitor(quality: LocationQuality = .platformDefault, interval: TimeInterval = 1.0, minimumInterval: TimeInterval = 0.0) -> AsyncThrowingStream<LocationEvent, Error> {
        logger.debug("starting location monitor quality=\(quality.rawValue) interval=\(interval) minimumInterval=\(minimumInterval)")
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: LocationEvent.self)

        #if SKIP
        listener = LocListener(callback: { location in
            logger.info("location update: \(location.latitude) \(location.longitude)")
            continuation.yield(with: .success(location))
        })
        let intervalMillis = Int64(interval * 1_000.0)
        // https://developer.android.com/reference/android/location/LocationRequest.Builder
        let builder = LocationRequest.Builder(intervalMillis)
        if let androidQuality = quality.androidQuality {
            builder.setQuality(androidQuality)
        }
        if minimumInterval > 0.0 {
            builder.setMinUpdateIntervalMillis(Int64(minimumInterval * 1_000.0))
        }
        let request = builder.build()
        do {
            locationManager.requestLocationUpdates(LocationManager.FUSED_PROVIDER, request, ProcessInfo.processInfo.androidContext.mainExecutor, listener!)
        } catch {
            logger.error("error requesting location updates: \(error) ")
            continuation.yield(with: .failure(error))
        }
        #else
        self.callback = { result in
            switch result {
            case .success(let location):
                logger.info("location update: \(location.latitude) \(location.longitude)")
                continuation.yield(with: .success(location))
            case .failure(let error):
                continuation.yield(with: .failure(error))
                self.callback = nil
            }
        }
        if let desiredAccuracy = quality.desiredAccuracy {
            locationManager.desiredAccuracy = desiredAccuracy
        }
        locationManager.startUpdatingLocation()
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
        return try await withCheckedThrowingContinuation { continuation in
            self.callback = { result in
                switch result {
                case .success(let location):
                    continuation.resume(returning: location)
                    self.locationManager.stopUpdatingLocation()
                    self.callback = nil
                case .failure(let error):
                    continuation.resume(throwing: error)
                    self.locationManager.stopUpdatingLocation()
                    self.callback = nil
                }
            }
            locationManager.startUpdatingLocation()
        }
        #else
        let context = ProcessInfo.processInfo.androidContext
        let locationManager = context.getSystemService(Context.LOCATION_SERVICE) as android.location.LocationManager
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
        logger.info("LocationProvider.didUpdateLocations: \(locations)")
        for location in locations {
            callback?(.success(LocationEvent(location: location)))
        }
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        logger.error("LocationProvider.didFailWithError: \(error)")
        callback?(.failure(error))
    }

    public func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: any Error) {
        logger.error("LocationProvider.monitoringDidFailFor: \(error)")
        callback?(.failure(error))
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
