# SkipDevice

The SkipDevice module is a dual-platform Skip framework that provides access to 
network reachability, location, and device sensor data.

## Network Reachability

You can check whether the device is currenly able to access the network with:

```swift
let isReachable: Bool = networkReachability.isNetworkReachable
```

### Network Reachability Permissions

In order to access the device's photos or media library, you will need to 
declare the permissions in the app's metadata.

On Android, the `app/src/main/AndroidManifest.xml` file will need to be edited to include:

```
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
```

## Location

You can request a single current device location with:

```swift
let provider = LocationProvider()
let location: LocationEvent = try await provider.fetchCurrentLocation()
logger.log("latitude: \(location.latitude) longitude: \(location.longitude) altitude: \(location.altitude)")
```

### Location Permissions

In order to access the device's location, you will need to 
declare the permissions in the app's metadata.

On Android, the `app/src/main/AndroidManifest.xml` file will need to be edited to include one of the
following permissions:

```
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
```

On iOS, you will need to add the `NSLocationWhenInUseUsageDescription` key to your `Darwin/AppName.xcconfig` file:

```
INFOPLIST_KEY_NSLocationWhenInUseUsageDescription = "This app uses your location to …"
```

## Motion

### Motion Permissions

On iOS, you will need to add the `NSMotionUsageDescription` key to your `Darwin/AppName.xcconfig` file:

```
INFOPLIST_KEY_NSMotionUsageDescription = "This app uses your motion information to …"
```


## Accelerometer

The `AccelerometerProvider` type provides an `AsyncStream<AccelerometerEvent>` of device accelerometer changes.

It can be used in a View like this:

```swift
import SwiftUI
import SkipDevice

struct AccelerometerView : View {
    @State var event: AccelerometerEvent?

    var body: some View {
        VStack {
            if let event = event {
                Text("x: \(event.x)")
                Text("y: \(event.y)")
                Text("z: \(event.z)")
            }
        }
        .task {
            let provider = AccelerometerProvider() // must retain reference
            for await event in provider.monitor() {
                self.event = event
                // if cancelled { break }
            }
            provider.stop()
        }
    }
}
```

## Gyroscope

The `GyroscopeProvider` type provides an `AsyncStream<GyroscopeEvent>` of device gyroscope changes.

It can be used in a View like this:

```swift
import SwiftUI
import SkipDevice

struct GyroscopeView : View {
    @State var event: GyroscopeEvent?

    var body: some View {
        VStack {
            if let event = event {
                Text("x: \(event.x)")
                Text("y: \(event.y)")
                Text("z: \(event.z)")
            }
        }
        .task {
            let provider = GyroscopeProvider() // must retain reference
            for await event in provider.monitor() {
                self.event = event
                // if cancelled { break }
            }
            provider.stop()
        }
    }
}
```


## Magnetometer

The `MagnetometerProvider` type provides an `AsyncStream<MagnetometerEvent>` of device magnetometer changes.

It can be used in a View like this:

```swift
import SwiftUI
import SkipDevice

struct MagnetometerView : View {
    @State var event: MagnetometerEvent?

    var body: some View {
        VStack {
            if let event = event {
                Text("x: \(event.x)") // X-axis magnetic field in microteslas
                Text("y: \(event.y)") // Y-axis magnetic field in microteslas
                Text("z: \(event.z)") // Z-axis magnetic field in microteslas
            }
        }
        .font(Font.body.monospaced())
        .task {
            let provider = MagnetometerProvider() // must retain reference
            for await event in provider.monitor() {
                self.event = event
                // if cancelled { break }
            }
            provider.stop()
        }
    }
}
```


## Barometer

The `BarometerProvider` type provides an `AsyncStream<BarometerEvent>` of device barometer changes.

It can be used in a View like this:

```swift
import SwiftUI
import SkipDevice

struct BarometerView : View {
    @State var event: BarometerEvent?

    var body: some View {
        VStack {
            if let event = event {
                Text("pressure: \(event.pressure)") // The recorded pressure, in kilopascals.
                Text("relativeAltitude: \(event.relativeAltitude)") // The change in altitude (in meters) since the first reported event.
            }
        }
        .font(Font.body.monospaced())
        .task {
            let provider = BarometerProvider() // must retain reference
            for await event in provider.monitor() {
                self.event = event
                // if cancelled { break }
            }
            provider.stop()
        }
    }
}
```

### Barometer Permissions

In order to access the device's barometer, you will need to 
declare the permissions in the app's metadata.

On Android, the `app/src/main/AndroidManifest.xml` file will need to be edited to include:

```
<uses-feature android:name="android.hardware.sensor.barometer" android:required="true" />
```


## Building

This project is a Swift Package Manager module that uses the
[Skip](https://skip.tools) plugin to transpile Swift into Kotlin.

Building the module requires that Skip be installed using 
[Homebrew](https://brew.sh) with `brew install skiptools/skip/skip`.
This will also install the necessary build prerequisites:
Kotlin, Gradle, and the Android build tools.

## Testing

The module can be tested using the standard `swift test` command
or by running the test target for the macOS destination in Xcode,
which will run the Swift tests as well as the transpiled
Kotlin JUnit tests in the Robolectric Android simulation environment.

Parity testing can be performed with `skip test`,
which will output a table of the test results for both platforms.

