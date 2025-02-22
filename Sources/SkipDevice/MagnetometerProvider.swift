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
import android.hardware.SensorEventListener2
#endif

private let logger: Logger = Logger(subsystem: "skip.device", category: "MagnetometerProvider") // adb logcat '*:S' 'skip.device.MagnetometerProvider:V'

/// A provider for device magnetometer events.
public class MagnetometerProvider {
    #if SKIP
    private let sensorManager = ProcessInfo.processInfo.androidContext.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private var listener: SensorEventListener2? = nil
    #elseif os(iOS) || os(watchOS)
    private let motionManager = CMMotionManager()
    #endif

    public init() {
    }

    deinit {
        stop()
    }
    
    /// Set the update interval for the magnetometer. Must be set before `monitor()` is invoked.
    public var updateInterval: TimeInterval? {
        didSet {
            #if os(iOS) || os(watchOS)
            if let interval = updateInterval {
                motionManager.magnetometerUpdateInterval = interval
            }
            #endif
        }
    }

    /// Returns `true` if the magnetometer is available on this device
    public var isAvailable: Bool {
        #if SKIP
        return sensorManager.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD) != nil
        #elseif os(iOS) || os(watchOS)
        return motionManager.isMagnetometerAvailable
        #else
        return false // macOS, etc.
        #endif
    }

    public func stop() {
        #if SKIP
        if listener != nil {
            sensorManager.unregisterListener(listener)
            listener = nil
        }
        #elseif os(iOS) || os(watchOS)
        motionManager.stopMagnetometerUpdates()
        #endif
    }

    // SKIP @nobridge // 'AsyncStream<MagnetometerEvent>' is not a bridged type
    public func monitor() -> AsyncStream<MagnetometerEvent> {
        logger.debug("monitor")
        let (stream, continuation) = AsyncStream.makeStream(of: MagnetometerEvent.self)

        #if SKIP
        if let sensor = sensorManager.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD) {
            listener = SensorEventHandler(onSensorChangedCallback: { event in
                continuation.yield(MagnetometerEvent(event: event))
            })

            // The rate sensor events are delivered at. This is only a hint to the system. Events may be received faster or slower than the specified rate. Usually events are received faster. The value must be one of SENSOR_DELAY_NORMAL, SENSOR_DELAY_UI, SENSOR_DELAY_GAME, or SENSOR_DELAY_FASTEST or, the desired delay between events in microseconds.
            var interval = SensorManager.SENSOR_DELAY_NORMAL
            if let updateInterval {
                interval = Int(updateInterval * 1_000_000) // microseconds
            }
            sensorManager.registerListener(listener, sensor, interval)
        }
        #elseif os(iOS) || os(watchOS)
        motionManager.startMagnetometerUpdates(to: OperationQueue.main) { data, error in
            if let error = error {
                logger.debug("magnetometer update error: \(error)")
                //continuation.finish(throwing: error) // would need to be AsyncThrowingStream
            } else if let data = data {
                continuation.yield(MagnetometerEvent(data: data))
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

public struct MagnetometerEvent {
    /// X-axis magnetic field in microteslas.
    public var x: Double
    /// Y-axis magnetic field in microteslas.
    public var y: Double
    /// Z-axis magnetic field in microteslas.
    public var z: Double
    /// The time when the logged item is valid.
    public var timestamp: TimeInterval

    #if SKIP
    // https://developer.android.com/reference/android/hardware/SensorEvent#values
    init(event: SensorEvent) {
        self.x = event.values[0].toDouble()
        self.y = event.values[1].toDouble()
        self.z = event.values[2].toDouble()
        self.timestamp = event.timestamp / 1_000_000_000.0 // nanoseconds

    }
    #elseif os(iOS) || os(watchOS)
    // https://developer.apple.com/documentation/coremotion/cmmagnetometerdata
    init(data: CMMagnetometerData) {
        self.x = data.magneticField.x
        self.y = data.magneticField.y
        self.z = data.magneticField.z
        self.timestamp = data.timestamp
    }
    #endif
}

#endif
