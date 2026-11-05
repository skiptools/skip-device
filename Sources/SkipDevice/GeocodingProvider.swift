// Copyright 2025–2026 Skip
// SPDX-License-Identifier: MPL-2.0
#if !SKIP_BRIDGE
import Foundation
#if canImport(OSLog)
import OSLog
#endif
#if !SKIP
import CoreLocation
#if canImport(MapKit)
import MapKit
#endif
#else
import android.location.Address
import android.location.Geocoder
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
#endif

private let logger: Logger = Logger(subsystem: "skip.device", category: "GeocodingProvider") // adb logcat '*:S' 'skip.device.GeocodingProvider:V'

/// Converts between coordinates and human-readable places.
///
/// Geocoding is a network service on both platforms: it needs no location permission, but it does
/// need network access (`android.permission.INTERNET` on Android). Requests are rate-limited by the
/// platform, so callers that geocode as the user types should debounce their queries.
///
/// On Darwin this uses `MKReverseGeocodingRequest`/`MKGeocodingRequest` on OS 26 and later, falling
/// back to `CLGeocoder` on earlier versions. On Android it uses
/// [`Geocoder`](https://developer.android.com/reference/android/location/Geocoder), whose
/// listener-based API is used on API 33+ and the blocking API (on a background dispatcher) below that.
public final class GeocodingProvider: @unchecked Sendable {
    private let locale: Locale

    /// Creates a provider whose results are localized for `locale`.
    public init(locale: Locale = Locale.current) {
        self.locale = locale
    }

    /// Returns `true` if a geocoding service is available on this device.
    ///
    /// This is always `true` on Darwin. On Android it reflects `Geocoder.isPresent()`, which is
    /// `false` on devices without a geocoding backend (e.g. those without Google Play services).
    public var isAvailable: Bool {
        #if SKIP
        return Geocoder.isPresent()
        #else
        return true
        #endif
    }

    /// Looks up the places at the given coordinate, most relevant first.
    ///
    /// Returns an empty array when the service finds nothing at that coordinate.
    public func reverseGeocode(latitude: Double, longitude: Double) async throws -> [GeocodedPlace] {
        logger.debug("reverseGeocode latitude=\(latitude) longitude=\(longitude)")
        #if SKIP
        let geocoder = try androidGeocoder()
        let addresses: kotlin.collections.List<Address>
        if android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU {
            addresses = suspendCancellableCoroutine { continuation in
                geocoder.getFromLocation(latitude, longitude, 1, GeocodeCallback(continuation: continuation))
            }
        } else {
            // SKIP NOWARN
            addresses = withContext(Dispatchers.IO) {
                geocoder.getFromLocation(latitude, longitude, 1) ?? listOf()
            }
        }
        return Self.places(from: addresses)
        #else
        let location = CLLocation(latitude: latitude, longitude: longitude)
        #if canImport(MapKit)
        if #available(iOS 26, macOS 26, tvOS 26, watchOS 26, *) {
            return try await Self.mapKitReverseGeocode(location: location, locale: locale)
        }
        #endif
        return try await Self.clReverseGeocode(location: location, locale: locale)
        #endif
    }

    /// Looks up the places matching a free-form address or place name, most relevant first.
    ///
    /// - Parameters:
    ///   - address: the text to search for, such as `"Koramangala, Bengaluru"` or `"1 Infinite Loop"`.
    ///   - maxResults: the most results to return. Darwin may return fewer than Android for the same query.
    /// - Returns: the matching places, or an empty array when nothing matches.
    public func geocode(address: String, maxResults: Int = 5) async throws -> [GeocodedPlace] {
        logger.debug("geocode address=\(address) maxResults=\(maxResults)")
        let query = address.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        if query.isEmpty || maxResults <= 0 {
            return []
        }
        #if SKIP
        let geocoder = try androidGeocoder()
        let addresses: kotlin.collections.List<Address>
        if android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU {
            addresses = suspendCancellableCoroutine { continuation in
                geocoder.getFromLocationName(query, maxResults, GeocodeCallback(continuation: continuation))
            }
        } else {
            // SKIP NOWARN
            addresses = withContext(Dispatchers.IO) {
                geocoder.getFromLocationName(query, maxResults) ?? listOf()
            }
        }
        return Self.places(from: addresses)
        #else
        var places: [GeocodedPlace]
        #if canImport(MapKit)
        if #available(iOS 26, macOS 26, tvOS 26, watchOS 26, *) {
            places = try await Self.mapKitGeocode(address: query, locale: locale)
        } else {
            places = try await Self.clGeocode(address: query, locale: locale)
        }
        #else
        places = try await Self.clGeocode(address: query, locale: locale)
        #endif
        if places.count > maxResults {
            places = Array(places.prefix(maxResults))
        }
        return places
        #endif
    }

    #if SKIP
    private func androidGeocoder() throws -> Geocoder {
        guard Geocoder.isPresent() else {
            throw GeocodingError(errorDescription: "No geocoding service is available on this device")
        }
        return Geocoder(ProcessInfo.processInfo.androidContext, locale.kotlin())
    }

    private static func places(from addresses: kotlin.collections.List<Address>) -> [GeocodedPlace] {
        var places: [GeocodedPlace] = []
        for address in addresses {
            // An Address without a coordinate is of no use to callers of either method.
			guard address.hasLatitude() && address.hasLongitude() else { continue }
			places.append(GeocodedPlace(address: address))
        }
        return places
    }
    #else
    private static func clReverseGeocode(location: CLLocation, locale: Locale) async throws -> [GeocodedPlace] {
        do {
            let placemarks = try await CLGeocoder().reverseGeocodeLocation(location, preferredLocale: locale)
            return placemarks.compactMap { GeocodedPlace(placemark: $0) }
        } catch let error as CLError where error.code == CLError.Code.geocodeFoundNoResult {
            return []
        }
    }

    private static func clGeocode(address: String, locale: Locale) async throws -> [GeocodedPlace] {
        do {
            let placemarks = try await CLGeocoder().geocodeAddressString(address, in: nil, preferredLocale: locale)
            return placemarks.compactMap { GeocodedPlace(placemark: $0) }
        } catch let error as CLError where error.code == CLError.Code.geocodeFoundNoResult {
            return []
        }
    }

    #if canImport(MapKit)
    @available(iOS 26, macOS 26, tvOS 26, watchOS 26, *)
    @MainActor
    private static func mapKitReverseGeocode(location: CLLocation, locale: Locale) async throws -> [GeocodedPlace] {
        guard let request = MKReverseGeocodingRequest(location: location) else {
            return []
        }
        request.preferredLocale = locale
        do {
            return try await request.mapItems.map { GeocodedPlace(mapItem: $0) }
        } catch let error as MKError where error.code == MKError.Code.placemarkNotFound {
            return []
        }
    }

    @available(iOS 26, macOS 26, tvOS 26, watchOS 26, *)
    @MainActor
    private static func mapKitGeocode(address: String, locale: Locale) async throws -> [GeocodedPlace] {
        guard let request = MKGeocodingRequest(addressString: address) else {
            return []
        }
        request.preferredLocale = locale
        do {
            return try await request.mapItems.map { GeocodedPlace(mapItem: $0) }
        } catch let error as MKError where error.code == MKError.Code.placemarkNotFound {
            return []
        }
    }
    #endif
    #endif
}

#if SKIP
/// Bridges `Geocoder`'s API 33 listener onto a coroutine, resuming it exactly once with either result.
///
/// `onError` has a default no-op implementation in `GeocodeListener`; overriding it is what keeps a
/// failed lookup from leaving the caller suspended forever.
final class GeocodeCallback: Geocoder.GeocodeListener {
    let continuation: kotlinx.coroutines.CancellableContinuation<kotlin.collections.List<Address>>

    init(continuation: kotlinx.coroutines.CancellableContinuation<kotlin.collections.List<Address>>) {
        self.continuation = continuation
    }

    override func onGeocode(addresses: kotlin.collections.MutableList<Address>) {
        if continuation.isActive {
            continuation.resume(addresses)
        }
    }

    override func onError(errorMessage: String?) {
        logger.error("geocoding failed: \(errorMessage ?? "unknown error")")
        if continuation.isActive {
            continuation.resumeWithException(GeocodingError(errorDescription: errorMessage ?? "Geocoding failed"))
        }
    }
}
#endif

public struct GeocodingError : LocalizedError {
    public var errorDescription: String?
}

/// A place returned by ``GeocodingProvider``.
///
/// Apart from the coordinate, every field is optional, and which ones are filled in depends on the
/// platform and OS version as well as the place itself:
///
/// | Field | Android `Address` | Darwin before 26 (`CLPlacemark`) | Darwin 26+ (`MKMapItem`) |
/// |---|---|---|---|
/// | `name` | `featureName` | `name` | `name` |
/// | `formattedAddress` | address lines | joined components | `address.fullAddress` |
/// | `subLocality` | `subLocality` | `subLocality` | – |
/// | `locality` | `locality` | `locality` | `addressRepresentations.cityName` |
/// | `administrativeArea` | `adminArea` | `administrativeArea` | – |
/// | `postalCode` | `postalCode` | `postalCode` | – |
/// | `country` | `countryName` | `country` | `addressRepresentations.regionName` |
/// | `countryCode` | `countryCode` | `isoCountryCode` | `addressRepresentations.region` |
///
/// MapKit's OS 26 types no longer expose the neighborhood, state or postal code as separate fields.
public struct GeocodedPlace: Hashable, Sendable {
    /// Latitude in degrees.
    public var latitude: Double
    /// Longitude in degrees.
    public var longitude: Double
    /// The name of the place, such as a landmark, business or street address.
    public var name: String?
    /// The full address on a single line, comma-separated.
    public var formattedAddress: String?
    /// The neighborhood or district, such as `"Mission District"`.
    public var subLocality: String?
    /// The city, such as `"San Francisco"`.
    public var locality: String?
    /// The state or province, such as `"CA"` or `"California"`.
    public var administrativeArea: String?
    /// The postal or ZIP code.
    public var postalCode: String?
    /// The localized country name.
    public var country: String?
    /// The ISO 3166-1 alpha-2 country code, such as `"US"`.
    public var countryCode: String?

    public init(latitude: Double, longitude: Double, name: String? = nil, formattedAddress: String? = nil, subLocality: String? = nil, locality: String? = nil, administrativeArea: String? = nil, postalCode: String? = nil, country: String? = nil, countryCode: String? = nil) {
        self.latitude = latitude
        self.longitude = longitude
		self.name = name?.nonEmpty
		self.formattedAddress = formattedAddress?.nonEmpty
		self.subLocality = subLocality?.nonEmpty
		self.locality = locality?.nonEmpty
		self.administrativeArea = administrativeArea?.nonEmpty
		self.postalCode = postalCode?.nonEmpty
		self.country = country?.nonEmpty
		self.countryCode = countryCode?.nonEmpty
    }

    #if SKIP
    /// https://developer.android.com/reference/android/location/Address
    init(address: Address) {
        self.init(
            latitude: address.getLatitude(),
            longitude: address.getLongitude(),
            name: address.getFeatureName(),
            formattedAddress: Self.addressLines(address),
            subLocality: address.getSubLocality(),
            locality: address.getLocality(),
            administrativeArea: address.getAdminArea(),
            postalCode: address.getPostalCode(),
            country: address.getCountryName(),
            countryCode: address.getCountryCode()
        )
    }

    private static func addressLines(_ address: Address) -> String? {
        var lines: [String?] = []
        if address.getMaxAddressLineIndex() >= 0 {
            for index in 0...address.getMaxAddressLineIndex() {
                lines.append(address.getAddressLine(index))
            }
        }
		return lines.joinedNonEmpty
    }
    #else
    /// https://developer.apple.com/documentation/corelocation/clplacemark
    init?(placemark: CLPlacemark) {
        guard let coordinate = placemark.location?.coordinate else {
            return nil
        }
		let street = [placemark.subThoroughfare, placemark.thoroughfare].joinedNonEmpty?.replacingOccurrences(of: ", ", with: " ")
        self.init(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            name: placemark.name,
			formattedAddress: [street, placemark.subLocality, placemark.locality, [placemark.administrativeArea, placemark.postalCode].joinedNonEmpty?.replacingOccurrences(of: ", ", with: " "), placemark.country].joinedNonEmpty,
            subLocality: placemark.subLocality,
            locality: placemark.locality,
            administrativeArea: placemark.administrativeArea,
            postalCode: placemark.postalCode,
            country: placemark.country,
            countryCode: placemark.isoCountryCode
        )
    }

    #if canImport(MapKit)
    /// https://developer.apple.com/documentation/mapkit/mkmapitem
    @available(iOS 26, macOS 26, tvOS 26, watchOS 26, *)
    init(mapItem: MKMapItem) {
        let representations = mapItem.addressRepresentations
        self.init(
            latitude: mapItem.location.coordinate.latitude,
            longitude: mapItem.location.coordinate.longitude,
            name: mapItem.name,
            formattedAddress: representations?.fullAddress(includingRegion: true, singleLine: true) ?? mapItem.address?.fullAddress,
            locality: representations?.cityName,
            country: representations?.regionName,
            countryCode: representations?.region?.identifier
        )
    }
    #endif
    #endif
}

extension String {
	var nonEmpty: String? {
		let trimmed = trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
		return trimmed.isEmpty ? nil : trimmed
	}
}

extension [String?] {
	/// Joins the non-empty values with `", "`, dropping consecutive duplicates (e.g. a `name` that repeats the street).
	var joinedNonEmpty: String? {
		let result: [String] = reduce(into: []) {
			guard let value = $1?.nonEmpty, $0.last != value else { return }
			$0.append(value)
		}
		return result.isEmpty ? nil : result.joined(separator: ", ")
	}
}

#endif
