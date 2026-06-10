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
import android.app.Activity
import android.app.Application
import android.content.ComponentCallbacks2
import android.content.res.Configuration
#endif

private let applicationRuntimeLogger: Logger = Logger(subsystem: "skip.device", category: "ApplicationRuntimeProvider") // adb logcat '*:S' 'skip.device.ApplicationRuntimeProvider:V'

/// A provider for app lifecycle and memory pressure events.
public final class ApplicationRuntimeProvider: @unchecked Sendable {
    #if SKIP
    private var androidObserver: ApplicationRuntimeAndroidObserver?
    #else
    private var notificationObservers: [NSObjectProtocol] = []
    #endif

    private let lock = NSLock()
    private var lifecycleMonitors: [LifecycleMonitor] = []
    private var memoryMonitors: [MemoryMonitor] = []
    private var lifecyclePhase: ApplicationLifecyclePhase = .unknown

    public init() {
        #if !SKIP
        lifecyclePhase = Self.initialLifecyclePhase()
        #endif
        start()
    }

    deinit {
        stop()
    }

    /// The most recently observed app lifecycle phase.
    public var currentLifecyclePhase: ApplicationLifecyclePhase {
        lock.lock()
        let phase = lifecyclePhase
        lock.unlock()
        return phase
    }

    /// Monitors foreground/background lifecycle events.
    public func monitorLifecycle() -> AsyncStream<ApplicationLifecycleEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            lock.lock()
            lifecycleMonitors.append(LifecycleMonitor(
                id: id,
                yield: { event in
                    continuation.yield(event)
                },
                finish: {
                    continuation.finish()
                }
            ))
            let phase = lifecyclePhase
            lock.unlock()
            continuation.yield(ApplicationLifecycleEvent(phase: phase))
            continuation.onTermination = { [weak self] _ in
                self?.removeLifecycleContinuation(id)
            }
        }
    }

    /// Monitors memory pressure events.
    public func monitorMemoryPressure() -> AsyncStream<MemoryPressureEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            lock.lock()
            memoryMonitors.append(MemoryMonitor(
                id: id,
                yield: { event in
                    continuation.yield(event)
                },
                finish: {
                    continuation.finish()
                }
            ))
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                self?.removeMemoryContinuation(id)
            }
        }
    }

    /// Stops monitoring platform runtime callbacks and finishes active streams.
    public func stop() {
        #if SKIP
        androidObserver?.stop()
        androidObserver = nil
        #else
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()
        #endif

        lock.lock()
        let lifecycle = lifecycleMonitors
        lifecycleMonitors.removeAll()
        let memory = memoryMonitors
        memoryMonitors.removeAll()
        lock.unlock()

        for monitor in lifecycle {
            monitor.finish()
        }
        for monitor in memory {
            monitor.finish()
        }
    }

    func publishLifecycle(_ phase: ApplicationLifecyclePhase) {
        let event = ApplicationLifecycleEvent(phase: phase)
        lock.lock()
        lifecyclePhase = phase
        let monitors = lifecycleMonitors
        lock.unlock()
        for monitor in monitors {
            monitor.yield(event)
        }
    }

    func publishMemoryPressure(_ level: MemoryPressureLevel) {
        let event = MemoryPressureEvent(level: level)
        lock.lock()
        let monitors = memoryMonitors
        lock.unlock()
        for monitor in monitors {
            monitor.yield(event)
        }
    }

    private func removeLifecycleContinuation(_ id: UUID) {
        lock.lock()
        var kept: [LifecycleMonitor] = []
        for monitor in lifecycleMonitors {
            if monitor.id != id {
                kept.append(monitor)
            }
        }
        lifecycleMonitors = kept
        lock.unlock()
    }

    private func removeMemoryContinuation(_ id: UUID) {
        lock.lock()
        var kept: [MemoryMonitor] = []
        for monitor in memoryMonitors {
            if monitor.id != id {
                kept.append(monitor)
            }
        }
        memoryMonitors = kept
        lock.unlock()
    }

    private func start() {
        #if SKIP
        guard androidObserver == nil else {
            return
        }
        let observer = ApplicationRuntimeAndroidObserver(provider: self)
        observer.start()
        androidObserver = observer
        #else
        guard notificationObservers.isEmpty else {
            return
        }
        #if canImport(UIKit)
        let center = NotificationCenter.default
        notificationObservers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil) { [weak self] _ in
            self?.publishLifecycle(ApplicationLifecyclePhase.active)
        })
        notificationObservers.append(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: nil) { [weak self] _ in
            self?.publishLifecycle(ApplicationLifecyclePhase.inactive)
        })
        notificationObservers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { [weak self] _ in
            self?.publishLifecycle(ApplicationLifecyclePhase.background)
        })
        notificationObservers.append(center.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: nil) { [weak self] _ in
            self?.publishLifecycle(ApplicationLifecyclePhase.terminated)
        })
        notificationObservers.append(center.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil) { [weak self] _ in
            self?.publishMemoryPressure(MemoryPressureLevel.warning)
        })
        #endif
        #endif
    }

    #if !SKIP
    private static func initialLifecyclePhase() -> ApplicationLifecyclePhase {
        #if canImport(UIKit)
        guard Thread.isMainThread else {
            return ApplicationLifecyclePhase.unknown
        }
        return MainActor.assumeIsolated {
            switch UIApplication.shared.applicationState {
            case .active:
                return ApplicationLifecyclePhase.active
            case .inactive:
                return ApplicationLifecyclePhase.inactive
            case .background:
                return ApplicationLifecyclePhase.background
            @unknown default:
                return ApplicationLifecyclePhase.unknown
            }
        }
        #else
        return ApplicationLifecyclePhase.unknown
        #endif
    }
    #endif
}

private struct LifecycleMonitor {
    var id: UUID
    var yield: (ApplicationLifecycleEvent) -> Void
    var finish: () -> Void
}

private struct MemoryMonitor {
    var id: UUID
    var yield: (MemoryPressureEvent) -> Void
    var finish: () -> Void
}

/// A coarse app lifecycle phase.
public enum ApplicationLifecyclePhase: String, Hashable, Sendable {
    case active
    case inactive
    case background
    case terminated
    case unknown
}

/// A coarse memory pressure level.
public enum MemoryPressureLevel: String, Hashable, Sendable {
    case warning
    case critical
}

/// An app lifecycle event.
public struct ApplicationLifecycleEvent: Hashable, Sendable {
    /// The lifecycle phase that was observed.
    public var phase: ApplicationLifecyclePhase
    /// The event timestamp in seconds since 1970.
    public var timestamp: TimeInterval

    public init(phase: ApplicationLifecyclePhase, timestamp: TimeInterval = Date().timeIntervalSince1970) {
        self.phase = phase
        self.timestamp = timestamp
    }
}

/// A memory pressure event.
public struct MemoryPressureEvent: Hashable, Sendable {
    /// The memory pressure level that was observed.
    public var level: MemoryPressureLevel
    /// The event timestamp in seconds since 1970.
    public var timestamp: TimeInterval

    public init(level: MemoryPressureLevel, timestamp: TimeInterval = Date().timeIntervalSince1970) {
        self.level = level
        self.timestamp = timestamp
    }
}

#if SKIP
private final class ApplicationRuntimeAndroidObserver: Application.ActivityLifecycleCallbacks, ComponentCallbacks2 {
    private weak var provider: ApplicationRuntimeProvider?
    private let application: Application?
    private var startedActivities = 0
    private var resumedActivities = 0

    init(provider: ApplicationRuntimeProvider) {
        self.provider = provider
        self.application = ProcessInfo.processInfo.androidContext.applicationContext as? Application
    }

    func start() {
        application?.registerActivityLifecycleCallbacks(self)
        application?.registerComponentCallbacks(self)
    }

    func stop() {
        application?.unregisterActivityLifecycleCallbacks(self)
        application?.unregisterComponentCallbacks(self)
    }

    override func onActivityResumed(activity: Activity) {
        resumedActivities += 1
        provider?.publishLifecycle(ApplicationLifecyclePhase.active)
    }

    override func onActivityPaused(activity: Activity) {
        if resumedActivities > 0 {
            resumedActivities -= 1
        }
        if resumedActivities == 0 && startedActivities > 0 {
            provider?.publishLifecycle(ApplicationLifecyclePhase.inactive)
        }
    }

    override func onActivityStopped(activity: Activity) {
        if startedActivities > 0 {
            startedActivities -= 1
        }
        if startedActivities == 0 {
            provider?.publishLifecycle(ApplicationLifecyclePhase.background)
        }
    }

    override func onActivityDestroyed(activity: Activity) {
        if activity.isFinishing && startedActivities == 0 {
            provider?.publishLifecycle(ApplicationLifecyclePhase.terminated)
        }
    }

    override func onActivityCreated(activity: Activity, savedInstanceState: android.os.Bundle?) {}
    override func onActivityStarted(activity: Activity) {
        startedActivities += 1
        if resumedActivities == 0 {
            provider?.publishLifecycle(ApplicationLifecyclePhase.inactive)
        }
    }
    override func onActivitySaveInstanceState(activity: Activity, outState: android.os.Bundle) {}

    override func onLowMemory() {
        provider?.publishMemoryPressure(MemoryPressureLevel.critical)
    }

    override func onTrimMemory(level: Int) {
        if level == ComponentCallbacks2.TRIM_MEMORY_RUNNING_CRITICAL || level == ComponentCallbacks2.TRIM_MEMORY_COMPLETE {
            provider?.publishMemoryPressure(MemoryPressureLevel.critical)
        } else {
            provider?.publishMemoryPressure(MemoryPressureLevel.warning)
        }
    }

    override func onConfigurationChanged(newConfig: Configuration) {}
}
#endif

#endif
