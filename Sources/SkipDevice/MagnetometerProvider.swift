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

private let logger: Logger = Logger(subsystem: "skip.device", category: "MagnetometerProvider") // adb logcat '*:S' 'skip.device.MagnetometerProvider:V'

/// A provider for device magnetometer events.
public class MagnetometerProvider {
    #if SKIP
    private let sensorManager = ProcessInfo.processInfo.androidContext.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private var listener: SensorEventHandler? = nil
    #elseif os(iOS) || os(watchOS)
    private let motionManager = CMMotionManager()
    #endif
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


    public init() {
    }

    deinit {
        stop()
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

    public func monitor() -> AsyncThrowingStream<MagnetometerEvent, Error> {
        logger.debug("starting magnetometer monitor")
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: MagnetometerEvent.self)

        #if SKIP
        listener = sensorManager.startSensorUpdates(type: Sensor.TYPE_MAGNETIC_FIELD, interval: updateInterval) { event in
            continuation.yield(MagnetometerEvent(event: event))
        }
        #elseif os(iOS) || os(watchOS)
        motionManager.startMagnetometerUpdates(to: OperationQueue.main) { data, error in
            if let error = error {
                logger.debug("magnetometer update error: \(error)")
                continuation.yield(with: .failure(error))
            } else if let data = data {
                continuation.yield(with: .success(MagnetometerEvent(data: data)))
            }
        }
        #endif

        continuation.onTermination = { [weak self] _ in
            logger.debug("cancelling magnetometer monitor")
            self?.stop()
        }

        return stream
    }
}

/// A data sample from the device's magnetometer.
///
/// Encapsulates:
/// - Darwin: [CMMagnetometerData](https://developer.apple.com/documentation/coremotion/cmmagnetometerdata)
/// - Android: [Sensor.TYPE_MAGNETIC_FIELD](https://developer.android.com/reference/android/hardware/SensorEvent#sensor.type_magnetic_field:)
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
    // https://developer.android.com/reference/android/hardware/SensorEvent#sensor.type_magnetic_field:
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
