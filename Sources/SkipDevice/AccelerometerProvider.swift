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

private let logger: Logger = Logger(subsystem: "skip.device", category: "AccelerometerProvider") // adb logcat '*:S' 'skip.device.AccelerometerProvider:V'

/// A provider for device accelerometer events.
public class AccelerometerProvider {
    #if SKIP
    private let sensorManager = ProcessInfo.processInfo.androidContext.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private var listener: SensorEventHandler? = nil
    #elseif os(iOS) || os(watchOS)
    private let motionManager = CMMotionManager()
    #endif
    /// Set the update interval for the accelerometer. Must be set before `monitor()` is invoked.
    public var updateInterval: TimeInterval? {
        didSet {
            #if os(iOS) || os(watchOS)
            if let interval = updateInterval {
                motionManager.accelerometerUpdateInterval = interval
            }
            #endif
        }
    }


    public init() {
    }

    deinit {
        stop()
    }
    
    /// Returns `true` if the accelerometer is available on this device
    public var isAvailable: Bool {
        #if SKIP
        return sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER) != nil
        #elseif os(iOS) || os(watchOS)
        return motionManager.isAccelerometerAvailable
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
        motionManager.stopAccelerometerUpdates()
        #endif
    }

    // SKIP @nobridge // 'AsyncStream<AccelerometerEvent>' is not a bridged type
    public func monitor() -> AsyncThrowingStream<AccelerometerEvent, Error> {
        logger.debug("starting accelerometer monitor")
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: AccelerometerEvent.self)

        #if SKIP
        listener = sensorManager.startSensorUpdates(type: Sensor.TYPE_ACCELEROMETER, interval: updateInterval) { event in
            continuation.yield(AccelerometerEvent(event: event))
        }
        #elseif os(iOS) || os(watchOS)
        motionManager.startAccelerometerUpdates(to: OperationQueue.main) { data, error in
            if let error = error {
                logger.debug("accelerometer update error: \(error)")
                continuation.yield(with: .failure(error))
            } else if let data = data {
                continuation.yield(with: .success(AccelerometerEvent(data: data)))
            }
        }
        #endif

        continuation.onTermination = { [weak self] _ in
            logger.debug("cancelling accelerometer monitor")
            self?.stop()
        }

        return stream
    }
}

/// A data sample from the device's three accelerometers.
///
/// Encapsulates:
/// - Darwin: [CMAccelerometerData](https://developer.apple.com/documentation/coremotion/cmaccelerometerdata)
/// - Android: [Sensor.TYPE_ACCELEROMETER](https://developer.android.com/reference/android/hardware/SensorEvent#sensor.type_accelerometer:)
public struct AccelerometerEvent {
    /// X-axis acceleration in G's (gravitational force).
    public var x: Double
    /// Y-axis acceleration in G's (gravitational force).
    public var y: Double
    /// Z-axis acceleration in G's (gravitational force).
    public var z: Double
    /// The time when the logged item is valid.
    public var timestamp: TimeInterval

    #if SKIP
    // https://developer.android.com/reference/android/hardware/SensorEvent#sensor.type_accelerometer:
    init(event: SensorEvent) {
        self.x = (-event.values[0] / SensorManager.GRAVITY_EARTH).toDouble()
        self.y = (-event.values[1] / SensorManager.GRAVITY_EARTH).toDouble()
        self.z = (-event.values[2] / SensorManager.GRAVITY_EARTH).toDouble()
        self.timestamp = event.timestamp / 1_000_000_000.0 // nanoseconds

    }
    #elseif os(iOS) || os(watchOS)
    // https://developer.apple.com/documentation/coremotion/cmaccelerometerdata
    init(data: CMAccelerometerData) {
        self.x = data.acceleration.x
        self.y = data.acceleration.y
        self.z = data.acceleration.z
        self.timestamp = data.timestamp
    }
    #endif
}

#endif
