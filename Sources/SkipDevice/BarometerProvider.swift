// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Lesser General Public License 3.0
// as published by the Free Software Foundation https://fsf.org

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

    public init() {
    }

    deinit {
        stop()
    }

    /// Set the update interval for the magnetometer. Must be set before `monitor()` is invoked.
    public var updateInterval: TimeInterval?

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

    // SKIP @nobridge // 'AsyncStream<BarometerEvent>' is not a bridged type
    public func monitor() -> AsyncStream<BarometerEvent> {
        logger.debug("monitor")
        let (stream, continuation) = AsyncStream.makeStream(of: BarometerEvent.self)

        #if SKIP
        if let sensor = sensorManager.getDefaultSensor(Sensor.TYPE_PRESSURE) {
            listener = SensorEventHandler(onSensorChangedCallback: { event in
                if self.referencePressure == nil {
                    // remember the initial reading so we can calculate relative altitiude
                    self.referencePressure = event.values[0]
                }
                continuation.yield(BarometerEvent(event: event, referencePressure: referencePressure!))
            })

            // The rate sensor events are delivered at. This is only a hint to the system. Events may be received faster or slower than the specified rate. Usually events are received faster. The value must be one of SENSOR_DELAY_NORMAL, SENSOR_DELAY_UI, SENSOR_DELAY_GAME, or SENSOR_DELAY_FASTEST or, the desired delay between events in microseconds.
            var interval = SensorManager.SENSOR_DELAY_NORMAL
            if let updateInterval {
                interval = Int(updateInterval * 1_000_000) // microseconds
            }
            sensorManager.registerListener(listener, sensor, interval)
        }
        #elseif os(iOS) || os(watchOS)
        altimeter.startRelativeAltitudeUpdates(to: OperationQueue.main) { data, error in
            if let error = error {
                logger.debug("barometer update error: \(error)")
                //continuation.finish(throwing: error) // would need to be AsyncThrowingStream
            } else if let data = data {
                continuation.yield(BarometerEvent(data: data))
            }
        }
        #endif

        continuation.onTermination = { [weak self] _ in
            logger.info("terminating")
            self?.stop()
        }

        return stream
    }
}

/// A data sample from the device's barometers.
public struct BarometerEvent {
    /// The recorded pressure, in kilopascals.
    public var pressure: Double
    /// The change in altitude (in meters) since the first reported event.
    public var relativeAltitude: Double
    /// The time when the logged item is valid.
    public var timestamp: TimeInterval

    #if SKIP
    // https://developer.android.com/reference/android/hardware/SensorEvent#values
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
