// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Lesser General Public License 3.0
// as published by the Free Software Foundation https://fsf.org

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
public class LocationProvider: NSObject {
    #if SKIP
    private let locationManager = ProcessInfo.processInfo.androidContext.getSystemService(Context.LOCATION_SERVICE) as LocationManager
    private var listener: LocListener?
    #else
    private let locationManager = CLLocationManager()
    private var callback: ((Result<LocationEvent, Error>) -> Void)?
    #endif

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
        return locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER) || locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
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

    // SKIP @nobridge // 'AsyncThrowingStream<LocationEvent, Error>' is not a bridged type
    public func monitor() -> AsyncThrowingStream<LocationEvent, Error> {
        logger.debug("starting location monitor")
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: LocationEvent.self)

        #if SKIP
        listener = LocListener(callback: { continuation.yield(with: .success($0)) })
        let intervalMillis = Int64(0)
        // https://developer.android.com/reference/android/location/LocationRequest.Builder
        let request = LocationRequest.Builder(intervalMillis).build() // TODO: setQuality, etc.
        do {
            locationManager.requestLocationUpdates(LocationManager.GPS_PROVIDER, request, ProcessInfo.processInfo.androidContext.mainExecutor, listener!)
        } catch {
            logger.error("error requesting location updates: \(error) ")
            continuation.yield(with: .failure(error))
        }
        #else
        self.callback = { result in
            switch result {
            case .success(let location):
                continuation.yield(with: .success(location))
            case .failure(let error):
                continuation.yield(with: .failure(error))
                self.callback = nil
            }
        }
        requestLocationOrAuthorization()
        #endif

        continuation.onTermination = { [weak self] _ in
            logger.debug("cancelling location monitor")
            self?.stop()
        }

        return stream
    }

    /// Issues a single-shot request for the current location
    public func fetchCurrentLocation() async throws -> LocationEvent {
        logger.debug("fetchCurrentLocation")
        #if !SKIP
        return try await withCheckedThrowingContinuation { continuation in
            self.callback = { result in
                switch result {
                case .success(let location):
                    continuation.resume(returning: location)
                    self.callback = nil
                case .failure(let error):
                    continuation.resume(throwing: error)
                    self.callback = nil
                }
            }
            requestLocationOrAuthorization()
        }
        #else
        return suspendCancellableCoroutine { continuation in
            let context = ProcessInfo.processInfo.androidContext
            let locationManager = context.getSystemService(Context.LOCATION_SERVICE) as android.location.LocationManager

            let locationListener = LocListener()

            locationListener.callback = {
                locationManager.removeUpdates(locationListener)
                continuation.resume($0)
            }

            locationManager.requestSingleUpdate(android.location.LocationManager.GPS_PROVIDER, locationListener, android.os.Looper.getMainLooper())

            continuation.invokeOnCancellation { _ in
                locationManager.removeUpdates(locationListener)
                continuation.cancel()
            }
        }
        #endif
    }
}

#if SKIP
struct LocListener : LocationListener {
    var callback: (LocationEvent) -> Void = { _ in }

    override func onLocationChanged(location: android.location.Location) {
        callback(LocationEvent(location: location))
    }

    override func onStatusChanged(provider: String?, status: Int, extras: android.os.Bundle?) {}
    //override func onProviderEnabled(provider: String?) {}
    //override func onProviderDisabled(provider: String?) {}
}
#else
extension LocationProvider: CLLocationManagerDelegate {
    private func requestLocationOrAuthorization() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        default:
            locationManager.startUpdatingLocation()
        }
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        logger.info("locationManager.locationManagerDidChangeAuthorization")
        if callback != nil {
            requestLocationOrAuthorization()
        }
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        logger.debug("locationManager.didUpdateLocations: \(locations)")
        for location in locations {
            callback?(.success(LocationEvent(location: location)))
        }
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        logger.error("locationManager.didFailWithError: \(error)")
        callback?(.failure(error))
    }
}
#endif

public struct LocationError : LocalizedError {
    public var errorDescription: String?
}

/// A lat/lon location (in degrees).
public struct LocationEvent {
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
        self.latitude = location.latitude
        self.longitude = location.longitude
        self.horizontalAccuracy = location.accuracy.toDouble()
        self.altitude = location.mslAltitudeMeters
        self.ellipsoidalAltitude = location.altitude
        self.verticalAccuracy = location.verticalAccuracyMeters.toDouble()
        self.speed = location.speed.toDouble()
        self.speedAccuracy = location.speedAccuracyMetersPerSecond.toDouble()
        self.course = location.bearing.toDouble()
        self.courseAccuracy = location.bearingAccuracyDegrees.toDouble()
        self.timestamp = location.time.toDouble() / 1_000.0
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
