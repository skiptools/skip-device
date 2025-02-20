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
import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume

typealias NSObject = AnyObject
#endif

let logger: Logger = Logger(subsystem: "skip.device", category: "LocationProvider") // adb logcat '*:S' 'skip.device.LocationProvider:V'

/// A current location fetcher.
///
/// Requires `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` in `App.xcconfig` and
/// `<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>` in `AndroidManifest.xml`.
public class LocationProvider: NSObject {
    #if !SKIP
    private let locationManager = CLLocationManager()
    private var completion: ((Result<Location, Error>) -> Void)?
    #endif

    public override init() {
        super.init()
        #if !SKIP
        locationManager.delegate = self
        #endif
    }

    public func fetchCurrentLocation() async throws -> Location {
        logger.log("fetchCurrentLocation")
        #if !SKIP
        return try await withCheckedThrowingContinuation { continuation in
            self.completion = { result in
                switch result {
                case .success(let location):
                    continuation.resume(returning: location)
                case .failure(let error):
                    continuation.resume(throwing: error)
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
class LocListener : android.location.LocationListener {
    var callback: (Location) -> Void = { _ in }

    override func onLocationChanged(location: android.location.Location) {
        callback(Location(latitude: location.latitude, longitude: location.longitude))
    }

    override func onStatusChanged(provider: String?, status: Int, extras: android.os.Bundle?) {}
    //override func onProviderEnabled(provider: String?) {}
    //override func onProviderDisabled(provider: String?) {}
}
#else
extension LocationProvider: CLLocationManagerDelegate {
    private func requestLocationOrAuthorization() {
        // unnecessary since the delegate will raise an error if the services are not enabled
        //if !CLLocationManager.locationServicesEnabled() {
        //    logger.error("location services not enabled")
        //    completion?(Result.failure(LocationError(errorDescription: "Location services not enabled")))
        //    return
        //}

        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        default:
            locationManager.requestLocation()
        }
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if completion != nil {
            requestLocationOrAuthorization()
        }
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last!
        completion?(.success(Location(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)))
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        completion?(.failure(error))
    }
}
#endif


public struct LocationError : LocalizedError {
    public var errorDescription: String?
}

/// A lat/lon location (in degrees).
public struct Location {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public func coordinates(fractionalDigits: Int? = nil) -> (latitude: Double, longitude: Double) {
        guard let fractionalDigits = fractionalDigits else {
            return (latitude, longitude)
        }
        let factor = pow(10.0, Double(fractionalDigits))
        return (latitude: Double(round(latitude * factor)) / factor, longitude: Double(round(longitude * factor)) / factor)
    }

    /// Calculate the distance from another Location using the Haversine formula and returns the distance in kilometers
    public func distance(from location: Location) -> Double {
        let lat1 = self.latitude
        let lon1 = self.longitude
        let lat2 = location.latitude
        let lon2 = location.longitude

        let dLat = (lat2 - lat1).toRadians
        let dLon = (lon2 - lon1).toRadians

        let slat: Double = sin(dLat / 2.0)
        let slon: Double = sin(dLon / 2.0)
        let a: Double = slat * slat + cos(lat1.toRadians) * cos(lat2.toRadians) * slon * slon
        let c: Double = 2.0 * atan2(sqrt(a), sqrt(1.0 - a))

        return c * 6371.0 // earthRadiusKilometers
    }
}

extension Double {
    var toRadians: Double {
        return self * .pi / 180.0
    }
}
#endif
