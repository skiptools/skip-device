// SPDX-License-Identifier: LGPL-3.0-only WITH LGPL-3.0-linking-exception
#if !SKIP_BRIDGE
import Foundation
#if canImport(OSLog)
import OSLog
#endif
#if !SKIP
import CoreMotion
#else
import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorManager
import android.hardware.SensorEvent
#endif

private let logger: Logger = Logger(subsystem: "skip.device", category: "BarometerProvider") // adb logcat '*:S' 'skip.device.BarometerProvider:V'

/// A provider for device Barometer events.
public class BarometerProvider {
    #if SKIP
    private let sensorManager = ProcessInfo.processInfo.androidContext.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private var listener: SensorEventHandler? = nil
    private var referencePressure: Float? = nil
    #elseif os(iOS) || os(watchOS)
    private let altimeter = CMAltimeter()
    #endif
    /// Set the update interval for the magnetometer. Must be set before `monitor()` is invoked.
    public var updateInterval: TimeInterval?

    public init() {
    }

    deinit {
        stop()
    }

    /// Returns `true` if the barometer is available on this device
    public var isAvailable: Bool {
        #if SKIP
        return sensorManager.getDefaultSensor(Sensor.TYPE_PRESSURE) != nil
        #elseif os(iOS) || os(watchOS)
        return CMAltimeter.isRelativeAltitudeAvailable()
        #else
        return false // macOS, etc.
        #endif
    }

    public func stop() {
        #if SKIP
        if listener != nil {
            sensorManager.unregisterListener(listener)
            listener = nil
            referencePressure = nil
        }
        #elseif os(iOS) || os(watchOS)
        altimeter.stopRelativeAltitudeUpdates()
        #endif
    }

    public func monitor() -> AsyncThrowingStream<BarometerEvent, Error> {
        logger.debug("starting barometer monitor")
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: BarometerEvent.self)

        #if SKIP
        listener = sensorManager.startSensorUpdates(type: Sensor.TYPE_PRESSURE, interval: updateInterval) { event in
            if self.referencePressure == nil {
                // remember the initial reading so we can calculate relative altitiude
                self.referencePressure = event.values[0]
            }
            continuation.yield(BarometerEvent(event: event, referencePressure: referencePressure!))
        }
        #elseif os(iOS) || os(watchOS)
        altimeter.startRelativeAltitudeUpdates(to: OperationQueue.main) { data, error in
            if let error = error {
                logger.debug("barometer update error: \(error)")
                continuation.yield(with: .failure(error))
            } else if let data = data {
                continuation.yield(with: .success(BarometerEvent(data: data)))
            }
        }
        #endif

        continuation.onTermination = { [weak self] _ in
            logger.debug("cancelling barometer monitor")
            self?.stop()
        }

        return stream
    }
}

/// A data sample from the device's barometers.
///
/// Encapsulates:
/// - Darwin: [CMAltitudeData](https://developer.apple.com/documentation/coremotion/cmaltitudedata)
/// - Android: [Sensor.TYPE_PRESSURE](https://developer.android.com/reference/android/hardware/SensorEvent#sensor.type_pressure:)
public struct BarometerEvent {
    /// The recorded pressure, in kilopascals.
    public var pressure: Double
    /// The change in altitude (in meters) since the first reported event.
    public var relativeAltitude: Double
    /// The time when the logged item is valid.
    public var timestamp: TimeInterval

    #if SKIP
    // https://developer.android.com/reference/android/hardware/SensorEvent#sensor.type_pressure:
    init(event: SensorEvent, referencePressure: Float) {
        self.pressure = event.values[0].toDouble() / 10.0 // convert from hPa to kPa
        self.relativeAltitude = SensorManager.getAltitude(referencePressure, event.values[0]).toDouble()
        self.timestamp = event.timestamp / 1_000_000_000.0 // nanoseconds
    }
    #elseif os(iOS) || os(watchOS)
    // https://developer.apple.com/documentation/coremotion/cmaltitudedata
    init(data: CMAltitudeData) {
        self.pressure = data.pressure.doubleValue
        self.relativeAltitude = data.relativeAltitude.doubleValue
        self.timestamp = data.timestamp
    }
    #endif
}

#endif
