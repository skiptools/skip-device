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

private let logger: Logger = Logger(subsystem: "skip.device", category: "AccelerometerProvider") // adb logcat '*:S' 'skip.device.AccelerometerProvider:V'

/// A motion provider.
public class AccelerometerProvider {
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
    public func monitor() -> AsyncStream<AccelerometerEvent> {
        logger.debug("monitor")
        let (stream, continuation) = AsyncStream.makeStream(of: AccelerometerEvent.self)

        #if SKIP
        if let sensor = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER) {
            listener = SensorEventHandler(onSensorChangedCallback: { event in
                // https://developer.android.com/reference/android/hardware/SensorEvent#values
                let event = AccelerometerEvent(
                    x: (-event.values[0] / SensorManager.GRAVITY_EARTH).toDouble(),
                    y: (-event.values[1] / SensorManager.GRAVITY_EARTH).toDouble(),
                    z: (-event.values[2] / SensorManager.GRAVITY_EARTH).toDouble(),
                    timestamp: event.timestamp / 1_000_000_000.0) // nanoseconds
                continuation.yield(event)
            })

            // The rate sensor events are delivered at. This is only a hint to the system. Events may be received faster or slower than the specified rate. Usually events are received faster. The value must be one of SENSOR_DELAY_NORMAL, SENSOR_DELAY_UI, SENSOR_DELAY_GAME, or SENSOR_DELAY_FASTEST or, the desired delay between events in microseconds.
            var interval = SensorManager.SENSOR_DELAY_NORMAL
            if let updateInterval {
                interval = Int(updateInterval * 1_000_000) // microseconds
            }
            sensorManager.registerListener(listener, sensor, interval)
        }
        #elseif os(iOS) || os(watchOS)
        motionManager.startAccelerometerUpdates(to: OperationQueue.main) { data, error in
            if let error = error {
                logger.debug("accelerometer update error: \(error)")
                //continuation.finish(throwing: error) // would need to be AsyncThrowingStream
            } else if let data = data {
                // https://developer.apple.com/documentation/coremotion/cmaccelerometerdata
                let event = AccelerometerEvent(x: data.acceleration.x, y: data.acceleration.y, z: data.acceleration.z, timestamp: data.timestamp)
                continuation.yield(event)
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

/// A data sample from the device's three accelerometers.
public struct AccelerometerEvent {
    /// X-axis acceleration in G's (gravitational force).
    public var x: Double
    /// Y-axis acceleration in G's (gravitational force).
    public var y: Double
    /// Z-axis acceleration in G's (gravitational force).
    public var z: Double
    /// The time when the logged item is valid.
    public var timestamp: TimeInterval
}

#if SKIP
struct SensorEventHandler: SensorEventListener2 {
    let onSensorChangedCallback: (_ event: SensorEvent) -> ()
    let onAccuracyChangedCallback: (_ sensor: Sensor, _ accuracy: Int) -> () = { _, _ in }
    let onFlushCompletedCallback: (_ sensor: Sensor) -> () = { _ in }

    override func onSensorChanged(event: SensorEvent) {
        onSensorChangedCallback(event)
    }

    override func onAccuracyChanged(sensor: Sensor, accuracy: Int) {
        onAccuracyChangedCallback(sensor, accuracy)
    }

    override func onFlushCompleted(sensor: Sensor) {
        onFlushCompletedCallback(sensor)
    }

}
#endif
#endif
