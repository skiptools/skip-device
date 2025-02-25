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

private let logger: Logger = Logger(subsystem: "skip.device", category: "GyroscopeProvider") // adb logcat '*:S' 'skip.device.GyroscopeProvider:V'

/// A provider for device gyroscope events.
public class GyroscopeProvider {
    #if SKIP
    private let sensorManager = ProcessInfo.processInfo.androidContext.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private var listener: SensorEventHandler? = nil
    #elseif os(iOS) || os(watchOS)
    private let motionManager = CMMotionManager()
    #endif
    /// Set the update interval for the gyroscope. Must be set before `monitor()` is invoked.
    public var updateInterval: TimeInterval? {
        didSet {
            #if os(iOS) || os(watchOS)
            if let interval = updateInterval {
                motionManager.gyroUpdateInterval = interval
            }
            #endif
        }
    }


    public init() {
    }

    deinit {
        stop()
    }
    
    /// Returns `true` if the gyroscope is available on this device
    public var isAvailable: Bool {
        #if SKIP
        return sensorManager.getDefaultSensor(Sensor.TYPE_GYROSCOPE) != nil
        #elseif os(iOS) || os(watchOS)
        return motionManager.isGyroAvailable
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
        motionManager.stopGyroUpdates()
        #endif
    }

    public func monitor() -> AsyncThrowingStream<GyroscopeEvent, Error> {
        logger.debug("starting gyroscope monitor")
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: GyroscopeEvent.self)

        #if SKIP
        listener = sensorManager.startSensorUpdates(type: Sensor.TYPE_GYROSCOPE, interval: updateInterval) { event in
            continuation.yield(GyroscopeEvent(event: event))
        }
        #elseif os(iOS) || os(watchOS)
        motionManager.startGyroUpdates(to: OperationQueue.main) { data, error in
            if let error = error {
                logger.debug("gyroscope update error: \(error)")
                continuation.yield(with: .failure(error))
            } else if let data = data {
                continuation.yield(with: .success(GyroscopeEvent(data: data)))
            }
        }
        #endif

        continuation.onTermination = { [weak self] _ in
            logger.debug("cancelling gyroscope monitor")
            self?.stop()
        }

        return stream
    }
}

/// A data sample from the device's three gyroscopes.
///
/// Encapsulates:
/// - Darwin: [CMGyroData](https://developer.apple.com/documentation/coremotion/cmgyrodata)
/// - Android: [Sensor.TYPE_GYROSCOPE](https://developer.android.com/reference/android/hardware/SensorEvent#sensor.type_gyroscope:)
public struct GyroscopeEvent {
    /// Angular speed around the x-axis
    public var x: Double
    /// Angular speed around the y-axis
    public var y: Double
    /// Angular speed around the z-axis
    public var z: Double
    /// The time when the logged item is valid.
    public var timestamp: TimeInterval

    #if SKIP
    // https://developer.android.com/reference/android/hardware/SensorEvent#sensor.type_gyroscope:
    init(event: SensorEvent) {
        self.x = event.values[0].toDouble()
        self.y = event.values[1].toDouble()
        self.z = event.values[2].toDouble()
        self.timestamp = event.timestamp / 1_000_000_000.0 // nanoseconds
    }
    #elseif os(iOS) || os(watchOS)
    // https://developer.apple.com/documentation/coremotion/cmgyrodata
    init(data: CMGyroData) {
        self.x = data.rotationRate.x
        self.y = data.rotationRate.y
        self.z = data.rotationRate.z
        self.timestamp = data.timestamp
    }
    #endif
}

#endif
