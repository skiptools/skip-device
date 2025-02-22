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
