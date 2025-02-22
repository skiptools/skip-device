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
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import android.hardware.Sensor
import android.hardware.SensorManager
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorEventListener2
#endif

private let logger: Logger = Logger(subsystem: "skip.device", category: "AccelerometerProvider") // adb logcat '*:S' 'skip.device.AccelerometerProvider:V'

/// A motion provider.
public class AccelerometerProvider {
    #if !SKIP
    #if os(iOS) || os(watchOS)
    private let motionManager = CMMotionManager()
    #endif
    #else
    private let sensorManager = ProcessInfo.processInfo.androidContext.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private var listener: SensorEventListener2? = nil
    #endif

    public init() {
    }

    deinit {
        stop()
    }

    // SKIP @nobridge // 'AsyncStream<AccelerometerEvent>' is not a bridged type
    public func monitor() -> AsyncStream<AccelerometerEvent> {
        logger.debug("monitor")
        let (stream, continuation) = AsyncStream.makeStream(of: AccelerometerEvent.self)

        #if SKIP
        if let sensor = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER) {
            listener = SensorEventHandler(
                onSensorChangedCallback: { event in
                    // https://developer.android.com/reference/android/hardware/SensorEvent#values
                    let event = AccelerometerEvent(x: (-event.values[0] / SensorManager.GRAVITY_EARTH).toDouble(), y: (-event.values[1] / SensorManager.GRAVITY_EARTH).toDouble(), z: (-event.values[2] / SensorManager.GRAVITY_EARTH).toDouble(), timestamp: event.timestamp / 1_000_000_000.0)
                    continuation.yield(event)
                },
                onAccuracyChangedCallback: { sensor, accuracy in
                },
                onFlushCompletedCallback: { sensor in
                }
            )
            sensorManager.registerListener(listener, sensor, SensorManager.SENSOR_DELAY_NORMAL)
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

    public func stop() {
        #if !SKIP
        #if os(iOS) || os(watchOS)
        motionManager.stopAccelerometerUpdates()
        #endif
        #else
        if listener != nil {
            sensorManager.unregisterListener(listener)
            listener = nil
        }
        #endif
    }
}

public struct AccelerometerEvent {
    public var x: Double
    public var y: Double
    public var z: Double
    public var timestamp: TimeInterval
}

#if SKIP
struct SensorEventHandler: SensorEventListener2 {
    let onSensorChangedCallback: (_ event: SensorEvent) -> ()
    let onAccuracyChangedCallback: (_ sensor: Sensor, _ accuracy: Int) -> ()
    let onFlushCompletedCallback: (_ sensor: Sensor) -> ()

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
