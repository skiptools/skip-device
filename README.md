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

You can also subscribe to a stream of location updates like so:

```swift
import SwiftUI
import SwiftKit // for PermissionManager
import SkipDevice

struct LocationView : View {
    @State var event: LocationEvent?

    var body: some View {
        VStack {
            if let event = event {
                Text("latitude: \(event.latitude)")
                Text("longitude: \(event.longitude)")
                Text("altitude: \(event.altitude)")
                Text("course: \(event.course)")
                Text("speed: \(event.speed)")
            }
        }
        .font(Font.body.monospaced())
        .task {
            // SkipKit provided PermissionManager, which creates a user-interface to request individual permissions
            if await PermissionManager.requestLocationPermission(precise: true, always: false).isAuthorized == false {
                logger.warning("permission refused for ACCESS_FINE_LOCATION")
                return
            }

            let provider = LocationProvider() // must retain reference
            provider.updateInterval = 1.0
            do {
                for try await event in provider.monitor() {
                    self.event = event
                    // if cancelled { break }
                }
            } catch {
                logger.error("error updating location: \(error)")
            }
            provider.stop()
        }
    }
}
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

The `AccelerometerProvider` type provides an `AsyncThrowingStream<AccelerometerEvent, Event>` of device accelerometer changes.

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
            provider.updateInterval = 0.1
            do {
                for try await event in provider.monitor() {
                    self.event = event
                    // if cancelled { break }
                }
            } catch {
                logger.error("error updating accelerometer: \(error)")
            }
            provider.stop()
        }
    }
}
```

## Gyroscope

The `GyroscopeProvider` type provides an `AsyncThrowingStream<GyroscopeEvent, Event>` of device gyroscope changes.

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
            provider.updateInterval = 0.1
            do {
                for try await event in provider.monitor() {
                    self.event = event
                    // if cancelled { break }
                }
            } catch {
                logger.error("error updating gyroscope: \(error)")
            }
            provider.stop()
        }
    }
}
```


## Magnetometer

The `MagnetometerProvider` type provides an `AsyncThrowingStream<MagnetometerEvent, Error>` of device magnetometer changes.

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
            provider.updateInterval = 0.1
            do {
                for try await event in provider.monitor() {
                    self.event = event
                    // if cancelled { break }
                }
            } catch {
                logger.error("error updating magnetometer: \(error)")
            }
            provider.stop()
        }
    }
}
```


## Barometer

The `BarometerProvider` type provides an `AsyncThrowingStream<BarometerEvent, Event>` of device barometer changes.

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
            provider.updateInterval = 0.1
            do {
                for try await event in provider.monitor() {
                    self.event = event
                    // if cancelled { break }
                }
            } catch {
                logger.error("error updating barometer: \(error)")
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

## Contributing

We welcome contributions to this package in the form of enhancements and bug fixes.

The general flow for contributing to this and any other Skip package is:

1. Fork this repository and enable actions from the "Actions" tab
2. Check out your fork locally
3. When developing alongside a Skip app, add the package to a [shared workspace](https://skip.tools/docs/contributing) to see your changes incorporated in the app
4. Push your changes to your fork and ensure the CI checks all pass in the Actions tab
5. Add your name to the Skip [Contributor Agreement](https://github.com/skiptools/clabot-config)
6. Open a Pull Request from your fork with a description of your changes

## License

This software is licensed under the
[GNU Lesser General Public License v3.0](https://spdx.org/licenses/LGPL-3.0-only.html),
with the following
[linking exception](https://spdx.org/licenses/LGPL-3.0-linking-exception.html)
to clarify that distribution to restricted environments (e.g., app stores)
is permitted:

> This software is licensed under the LGPL3, included below.
> As a special exception to the GNU Lesser General Public License version 3
> ("LGPL3"), the copyright holders of this Library give you permission to
> convey to a third party a Combined Work that links statically or dynamically
> to this Library without providing any Minimal Corresponding Source or
> Minimal Application Code as set out in 4d or providing the installation
> information set out in section 4e, provided that you comply with the other
> provisions of LGPL3 and provided that you meet, for the Application the
> terms and conditions of the license(s) which apply to the Application.
> Except as stated in this special exception, the provisions of LGPL3 will
> continue to comply in full to this Library. If you modify this Library, you
> may apply this exception to your version of this Library, but you are not
> obliged to do so. If you do not wish to do so, delete this exception
> statement from your version. This exception does not (and cannot) modify any
> license terms which apply to the Application, with which you must still
> comply.

