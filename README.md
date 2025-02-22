# SkipDevice

The SkipDevice module is a dual-platform Skip framework that provides access to 
device sensor data such as network reachability and location.

## Network Reachability

You can check whether the device is currenly able to access the network with:

```swift
let isReachable: Bool = networkReachability.isNetworkReachable
```

### Permissions

In order to access the device's photos or media library, you will need to 
declare the permissions in the app's metadata.

On Android, the `app/src/main/AndroidManifest.xml` file will need to be edited to include:

```
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
```

## Location

You can request the current device location with:

```swift
let provider = LocationProvider()
let location: LocationEvent = try await provider.fetchCurrentLocation()
logger.log("latitude: \(location.latitude) longitude: \(location.longitude) altitude: \(location.altitude)")
```

### Permissions

In order to access the device's location, you will need to 
declare the permissions in the app's metadata.

On Android, the `app/src/main/AndroidManifest.xml` file will need to be edited to include:

```
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
```

On iOS, you will need to add the `NSLocationWhenInUseUsageDescription` key to your `Darwin/AppName.xcconfig` file:

```
INFOPLIST_KEY_NSLocationWhenInUseUsageDescription = "This app uses your location to …"
```

## Accelerometer

The `AccelerometerProvider` type provides an `AsyncStream<AccelerometerEvent>` of device accelerometer changes.

It can be used in a View like this:

```swift
struct AccelerometerView : View {
    @State var orientation: AccelerometerEvent?

    var body: some View {
        VStack {
            if let orientation = orientation {
                Text("x: \(orientation.x)")
                Text("y: \(orientation.y)")
                Text("z: \(orientation.z)")
            }
        }
        .task {
            let provider = AccelerometerProvider()
            for await event in provider.monitor() {
                self.orientation = event
            }
            provider.stop()
        }
    }
}
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

