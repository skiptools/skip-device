// Copyright 2025–2026 Skip
// SPDX-License-Identifier: MPL-2.0
#if !SKIP_BRIDGE
import Foundation
#if canImport(OSLog)
import OSLog
#endif
#if !SKIP
#if os(watchOS)
import Network
#else
import SystemConfiguration
#endif
#else
import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
#endif

private let logger: Logger = Logger(subsystem: "skip.device", category: "NetworkReachability") // adb logcat '*:S' 'skip.device.NetworkReachability:V'

/// Provides general information for a Skip app.
public class NetworkReachability {

    /// Returns true if the network is currently reachable
    public static var isNetworkReachable: Bool {
        logger.debug("isNetworkReachable")
        #if os(watchOS)
        return WatchNetworkStatus.shared.isReachable
        #elseif !SKIP
        var zeroAddress = sockaddr_in()
        zeroAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        zeroAddress.sin_family = sa_family_t(AF_INET)

        guard let defaultRouteReachability = withUnsafePointer(to: &zeroAddress, {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                SCNetworkReachabilityCreateWithAddress(nil, $0)
            }
        }) else {
            return false
        }

        var flags: SCNetworkReachabilityFlags = []
        guard SCNetworkReachabilityGetFlags(defaultRouteReachability, &flags) else {
            return false
        }

        let isReachable = flags.contains(.reachable)
        let needsConnection = flags.contains(.connectionRequired)

        return isReachable && !needsConnection
        #else
        let context = ProcessInfo.processInfo.androidContext
        let connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

        if Build.VERSION.SDK_INT >= Build.VERSION_CODES.M {
            guard let network = connectivityManager.activeNetwork else { return false }
            guard let activeNetwork = connectivityManager.getNetworkCapabilities(network) else { return false }

            if activeNetwork.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) { return true }
            if activeNetwork.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) { return true }
            if activeNetwork.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) { return true }

            return false
        } else {
            // older devices…
            let networkInfo = connectivityManager.activeNetworkInfo
            return networkInfo != nil && networkInfo.isConnected
        }
        #endif
    }
}
#endif


#if os(watchOS) && !SKIP_BRIDGE
private final class WatchNetworkStatus: @unchecked Sendable {
    static let shared = WatchNetworkStatus()

    private let monitor = NWPathMonitor()
    private let lock = NSLock()

    // Let network requests proceed until the first path update arrives.
    private var reachable = true

    var isReachable: Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.reachable
    }

    private init() {
        self.monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.lock()
            self.reachable = path.status == .satisfied
            self.lock.unlock()
        }

        self.monitor.start(queue: DispatchQueue(label: "skip.device.watch-network"))
    }
}
#endif
