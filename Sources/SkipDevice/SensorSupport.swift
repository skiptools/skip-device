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

#if SKIP

extension SensorManager {
    func startSensorUpdates(type: Int, interval: TimeInterval?, callback: (SensorEvent) -> ()) -> SensorEventHandler? {
        guard let sensor = getDefaultSensor(type) else {
            return nil
        }

        let listener = SensorEventHandler(onSensorChangedCallback: { event in
            callback(event)
        })

        // The rate sensor events are delivered at. This is only a hint to the system. Events may be received faster or slower than the specified rate. Usually events are received faster. The value must be one of SENSOR_DELAY_NORMAL, SENSOR_DELAY_UI, SENSOR_DELAY_GAME, or SENSOR_DELAY_FASTEST or, the desired delay between events in microseconds.
        var updateInterval = SensorManager.SENSOR_DELAY_NORMAL
        if let interval {
            updateInterval = Int(interval * 1_000_000) // microseconds
        }

        registerListener(listener, sensor, updateInterval)
        return listener
    }
}

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
