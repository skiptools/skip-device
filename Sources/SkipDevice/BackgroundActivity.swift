// Copyright 2025-2026 Skip
// SPDX-License-Identifier: MPL-2.0
#if !SKIP_BRIDGE
import Foundation
#if canImport(OSLog)
import OSLog
#endif
#if !SKIP
#if canImport(UIKit)
import UIKit
#endif
#else
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
#endif

private let backgroundActivityLogger: Logger = Logger(subsystem: "skip.device", category: "BackgroundActivity") // adb logcat '*:S' 'skip.device.BackgroundActivity:V'

/// Starts and ends finite user-visible background work.
public final class BackgroundActivity {
    private init() {
    }

    /// Begins a finite background activity and returns its identifier.
    public static func begin(_ request: BackgroundActivityRequest) async throws -> String {
        #if SKIP
        return try BackgroundActivityAndroidHost.begin(request)
        #elseif canImport(UIKit)
        return try await MainActor.run {
            let identifier = UUID().uuidString
            let task = UIApplication.shared.beginBackgroundTask(withName: request.name) {
                Task { @MainActor in
                    BackgroundActivityDarwinRegistry.shared.expire(identifier)
                }
            }
            guard task != .invalid else {
                throw BackgroundActivityError(errorDescription: "Unable to begin background activity.")
            }
            BackgroundActivityDarwinRegistry.shared.store(identifier: identifier, task: task)
            return identifier
        }
        #else
        throw BackgroundActivityError(errorDescription: "Background activity is not available on this platform.")
        #endif
    }

    /// Ends a background activity previously returned by `begin(_:)`.
    public static func end(_ identifier: String) async {
        #if SKIP
        BackgroundActivityAndroidHost.end(identifier)
        #elseif canImport(UIKit)
        await MainActor.run {
            BackgroundActivityDarwinRegistry.shared.end(identifier)
        }
        #endif
    }

    #if SKIP
    static func serviceType(for reason: BackgroundActivityReason) -> Int {
        switch reason {
        case BackgroundActivityReason.localNetworkTransfer:
            return ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
        case BackgroundActivityReason.mediaProcessing:
            if Build.VERSION.SDK_INT >= 35 {
                return ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROCESSING
            }
            return ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
        case BackgroundActivityReason.connectedDeviceTransfer:
            return ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
        case BackgroundActivityReason.shortCriticalWork:
            if Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE {
                return ServiceInfo.FOREGROUND_SERVICE_TYPE_SHORT_SERVICE
            }
            return ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
        }
    }
    #endif
}

/// Describes a finite background activity.
public struct BackgroundActivityRequest: Hashable, Sendable {
    /// User-visible activity name.
    public var name: String
    /// The platform reason used to choose an Android foreground-service type.
    public var reason: BackgroundActivityReason
    /// Optional user-visible detail for the Android foreground notification.
    public var detail: String
    /// Android notification channel identifier.
    public var notificationChannelID: String
    /// Android foreground notification identifier.
    public var notificationID: Int
    /// Android drawable resource name for the foreground notification icon.
    public var notificationIconResourceName: String

    public init(
        name: String,
        reason: BackgroundActivityReason = BackgroundActivityReason.shortCriticalWork,
        detail: String = "",
        notificationChannelID: String = "tools.skip.device.background_activity",
        notificationID: Int = 41_001,
        notificationIconResourceName: String = "ic_notification"
    ) {
        self.name = name
        self.reason = reason
        self.detail = detail
        self.notificationChannelID = notificationChannelID
        self.notificationID = notificationID
        self.notificationIconResourceName = notificationIconResourceName
    }
}

/// The reason a background activity needs additional runtime.
public enum BackgroundActivityReason: String, Hashable, Sendable {
    case localNetworkTransfer
    case mediaProcessing
    case connectedDeviceTransfer
    case shortCriticalWork
}

/// An error starting or managing a background activity.
public struct BackgroundActivityError: LocalizedError {
    public var errorDescription: String?

    public init(errorDescription: String?) {
        self.errorDescription = errorDescription
    }
}

#if !SKIP && canImport(UIKit)
@MainActor
private final class BackgroundActivityDarwinRegistry: @unchecked Sendable {
    static let shared = BackgroundActivityDarwinRegistry()

    private let lock = NSLock()
    private var tasks: [String: UIBackgroundTaskIdentifier] = [:]

    private init() {
    }

    func store(identifier: String, task: UIBackgroundTaskIdentifier) {
        lock.lock()
        tasks[identifier] = task
        lock.unlock()
    }

    func end(_ identifier: String) {
        lock.lock()
        let task = tasks.removeValue(forKey: identifier)
        lock.unlock()
        if let task {
            UIApplication.shared.endBackgroundTask(task)
        }
    }

    func expire(_ identifier: String) {
        end(identifier)
    }
}
#endif

#if SKIP
private enum BackgroundActivityAndroidHost {
    static func begin(_ request: BackgroundActivityRequest) throws -> String {
        let identifier = UUID().uuidString
        let context = ProcessInfo.processInfo.androidContext.applicationContext
        let intent = BackgroundActivityService.intent(context: context)
        intent.setAction(BackgroundActivityService.actionBegin)
        intent.putExtra(BackgroundActivityService.extraIdentifier, identifier)
        intent.putExtra(BackgroundActivityService.extraName, request.name)
        intent.putExtra(BackgroundActivityService.extraReason, request.reason.rawValue)
        intent.putExtra(BackgroundActivityService.extraDetail, request.detail)
        intent.putExtra(BackgroundActivityService.extraChannelID, request.notificationChannelID)
        intent.putExtra(BackgroundActivityService.extraNotificationID, request.notificationID)
        intent.putExtra(BackgroundActivityService.extraIconResourceName, request.notificationIconResourceName)
        do {
            ContextCompat.startForegroundService(context, intent)
            return identifier
        } catch {
            throw BackgroundActivityError(errorDescription: "Unable to begin background activity: \(error)")
        }
    }

    static func end(_ identifier: String) {
        let context = ProcessInfo.processInfo.androidContext.applicationContext
        let intent = BackgroundActivityService.intent(context: context)
        intent.setAction(BackgroundActivityService.actionEnd)
        intent.putExtra(BackgroundActivityService.extraIdentifier, identifier)
        context.startService(intent)
    }
}

/// Generic foreground service backing Android background activities.
class BackgroundActivityService: Service {
    static let actionBegin = "tools.skip.device.background_activity.BEGIN"
    static let actionEnd = "tools.skip.device.background_activity.END"
    static let extraIdentifier = "tools.skip.device.background_activity.identifier"
    static let extraName = "tools.skip.device.background_activity.name"
    static let extraReason = "tools.skip.device.background_activity.reason"
    static let extraDetail = "tools.skip.device.background_activity.detail"
    static let extraChannelID = "tools.skip.device.background_activity.channel_id"
    static let extraNotificationID = "tools.skip.device.background_activity.notification_id"
    static let extraIconResourceName = "tools.skip.device.background_activity.icon_resource_name"

    private var activeRequests: [String: BackgroundActivityRequest] = [:]

    override init() {
        super.init()
    }

    static func intent(context: Context) -> Intent {
        let intent = Intent()
        intent.setClassName(context, "skip.device.BackgroundActivityService")
        return intent
    }

    override func onBind(intent: Intent?) -> IBinder? {
        return nil
    }

    override func onStartCommand(intent: Intent?, flags: Int, startId: Int) -> Int {
        guard let intent else {
            return Service.START_NOT_STICKY
        }

        let action = intent.getAction()
        let identifier = intent.getStringExtra(Self.extraIdentifier) ?? ""
        if action == Self.actionBegin {
            guard let request = request(from: intent) else {
                stopSelf(startId)
                return Service.START_NOT_STICKY
            }
            activeRequests[identifier] = request
            startForeground(for: request)
        } else if action == Self.actionEnd {
            activeRequests[identifier] = nil
            if let request = activeRequests.values.first {
                startForeground(for: request)
            } else {
                ServiceCompat.stopForeground(self, ServiceCompat.STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }

        return Service.START_NOT_STICKY
    }

    override func onTimeout(startId: Int) {
        activeRequests.removeAll()
        stopSelf(startId)
    }

    override func onTimeout(startId: Int, fgsType: Int) {
        activeRequests.removeAll()
        stopSelf(startId)
    }

    private func request(from intent: Intent) -> BackgroundActivityRequest? {
        guard let name = intent.getStringExtra(Self.extraName), !name.isEmpty else {
            return nil
        }
        let reasonRawValue = intent.getStringExtra(Self.extraReason) ?? BackgroundActivityReason.shortCriticalWork.rawValue
        let reason = BackgroundActivityReason(rawValue: reasonRawValue) ?? BackgroundActivityReason.shortCriticalWork
        let detail = intent.getStringExtra(Self.extraDetail) ?? ""
        let channelID = intent.getStringExtra(Self.extraChannelID) ?? "tools.skip.device.background_activity"
        let notificationID = intent.getIntExtra(Self.extraNotificationID, 41_001)
        let iconResourceName = intent.getStringExtra(Self.extraIconResourceName) ?? "ic_notification"
        return BackgroundActivityRequest(
            name: name,
            reason: reason,
            detail: detail,
            notificationChannelID: channelID,
            notificationID: notificationID,
            notificationIconResourceName: iconResourceName
        )
    }

    private func startForeground(for request: BackgroundActivityRequest) {
        createNotificationChannel(request.notificationChannelID)
        let notification = notificationBuilder(for: request).build()
        let serviceType = BackgroundActivity.serviceType(for: request.reason)
        ServiceCompat.startForeground(self, request.notificationID, notification, serviceType)
    }

    private func createNotificationChannel(_ channelID: String) {
        if Build.VERSION.SDK_INT >= Build.VERSION_CODES.O {
            let notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            let appName = getApplicationInfo().loadLabel(getPackageManager()).toString()
            notificationManager.createNotificationChannel(NotificationChannel(channelID, appName, NotificationManager.IMPORTANCE_LOW))
        }
    }

    private func notificationBuilder(for request: BackgroundActivityRequest) -> NotificationCompat.Builder {
        let builder = NotificationCompat.Builder(self, request.notificationChannelID)
        builder.setContentTitle(request.name)
        builder.setOngoing(true)
        builder.setSmallIcon(notificationIconResourceID(named: request.notificationIconResourceName))

        if !request.detail.isEmpty {
            builder.setContentText(request.detail)
        }
        if let launchIntent = getPackageManager().getLaunchIntentForPackage(getPackageName()) {
            let flags = PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT
            let pendingIntent = PendingIntent.getActivity(self, request.notificationID, launchIntent, flags)
            builder.setContentIntent(pendingIntent)
        }
        return builder
    }

    private func notificationIconResourceID(named name: String) -> Int {
        var resourceID = getResources().getIdentifier(name, "drawable", getPackageName())
        if resourceID == 0 {
            resourceID = getResources().getIdentifier("ic_notification", "drawable", getPackageName())
        }
        if resourceID == 0 {
            resourceID = getResources().getIdentifier("ic_launcher", "mipmap", getPackageName())
        }
        if resourceID == 0 {
            resourceID = android.R.drawable.stat_sys_upload
        }
        return resourceID
    }
}
#endif

#endif
