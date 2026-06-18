// Copyright 2025-2026 Skip
// SPDX-License-Identifier: MPL-2.0
#if !SKIP_BRIDGE
import Foundation
#if !SKIP
#if canImport(UIKit)
import UIKit
#endif
#else
import android.os.Build
import android.provider.Settings
#endif

/// Describes the current device using stable, low-level platform identity fields.
public struct DeviceIdentity: Hashable, Sendable {
    /// User-visible device name when the platform exposes one.
    public var name: String?
    /// Platform model string, such as an Apple model identifier or Android `Build.MODEL`.
    public var model: String?
    /// Localized Apple model string when available.
    public var localizedModel: String?
    /// Platform operating system name.
    public var systemName: String?
    /// Platform operating system version.
    public var systemVersion: String?
    /// App/vendor-scoped stable identifier when available.
    public var vendorIdentifier: String?
    /// Device manufacturer, such as `Apple`, `Google`, or `Samsung`.
    public var manufacturer: String?
    /// Android `Build.BRAND` when available.
    public var brand: String?
    /// Android `Build.DEVICE` when available.
    public var device: String?
    /// Android `Build.PRODUCT` when available.
    public var product: String?

    public init(
        name: String? = nil,
        model: String? = nil,
        localizedModel: String? = nil,
        systemName: String? = nil,
        systemVersion: String? = nil,
        vendorIdentifier: String? = nil,
        manufacturer: String? = nil,
        brand: String? = nil,
        device: String? = nil,
        product: String? = nil
    ) {
        self.name = Self.nonEmpty(name)
        self.model = Self.nonEmpty(model)
        self.localizedModel = Self.nonEmpty(localizedModel)
        self.systemName = Self.nonEmpty(systemName)
        self.systemVersion = Self.nonEmpty(systemVersion)
        self.vendorIdentifier = Self.nonEmpty(vendorIdentifier)
        self.manufacturer = Self.nonEmpty(manufacturer)
        self.brand = Self.nonEmpty(brand)
        self.device = Self.nonEmpty(device)
        self.product = Self.nonEmpty(product)
    }

    /// Returns the current platform device identity.
    public static var current: DeviceIdentity {
        #if SKIP
        let context = ProcessInfo.processInfo.androidContext
        let contentResolver = context.contentResolver
        let deviceName = Settings.Global.getString(contentResolver, "device_name")
        let androidID = Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)
        return DeviceIdentity(
            name: deviceName,
            model: Build.MODEL,
            systemName: "Android",
            systemVersion: Build.VERSION.RELEASE,
            vendorIdentifier: androidID,
            manufacturer: Build.MANUFACTURER,
            brand: Build.BRAND,
            device: Build.DEVICE,
            product: Build.PRODUCT
        )
        #elseif canImport(UIKit)
        guard Thread.isMainThread else {
            return appleFallbackIdentity()
        }
        return MainActor.assumeIsolated {
            let device = UIDevice.current
            return DeviceIdentity(
                name: device.name,
                model: device.model,
                localizedModel: device.localizedModel,
                systemName: device.systemName,
                systemVersion: device.systemVersion,
                vendorIdentifier: device.identifierForVendor?.uuidString,
                manufacturer: "Apple",
                brand: "Apple"
            )
        }
        #else
        return DeviceIdentity(
            name: Host.current().localizedName,
            model: machineIdentifier(),
            systemName: ProcessInfo.processInfo.operatingSystemVersionString,
            systemVersion: ProcessInfo.processInfo.operatingSystemVersionString
        )
        #endif
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    #if !SKIP && canImport(UIKit)
    private static func appleFallbackIdentity() -> DeviceIdentity {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return DeviceIdentity(
            systemName: appleSystemName(),
            systemVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            manufacturer: "Apple",
            brand: "Apple"
        )
    }

    private static func appleSystemName() -> String {
        #if os(tvOS)
        return "tvOS"
        #elseif os(watchOS)
        return "watchOS"
        #elseif os(visionOS)
        return "visionOS"
        #elseif targetEnvironment(macCatalyst)
        return "macOS"
        #elseif os(iOS)
        return "iOS"
        #else
        return "Apple"
        #endif
    }
    #endif

    #if !SKIP && !canImport(UIKit)
    private static func machineIdentifier() -> String? {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingCString: $0)
            }
        }
    }
    #endif
}
#endif
