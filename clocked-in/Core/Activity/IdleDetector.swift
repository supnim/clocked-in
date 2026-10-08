import Foundation
import AppKit
import CoreGraphics
import OSLog

/// Detects user idleness by polling the system's "seconds since last input event"
/// (`CGEventSource.secondsSinceLastEventType`). Works in the App Sandbox without
/// Input Monitoring / Accessibility permissions (no global event monitors).
@MainActor
@Observable
final class IdleDetector {
    static let shared = IdleDetector()

    private let logger = Logger(subsystem: "com.clockedin", category: "IdleDetector")

    @ObservationIgnored
    private var pollTimer: Timer?
    private let idleThreshold: TimeInterval = 15 * 60 // 15 minutes
    private let pollInterval: TimeInterval = 15

    @ObservationIgnored
    private var isRunning = false

    /// Last idle state reported to PresenceManager
    @ObservationIgnored
    private var isIdle = false

    private init() {
        // Don't start automatically - wait for explicit start() call
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        isIdle = false
        startPolling()
        logger.debug("IdleDetector started")
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        cleanup()
        logger.debug("IdleDetector stopped")
    }

    nonisolated deinit {
        // Singleton; timer is invalidated in stop()/cleanup()
    }

    var isUserActive: Bool {
        Self.systemIdleTime() < idleThreshold
    }

    var timeSinceLastActivity: TimeInterval {
        Self.systemIdleTime()
    }

    /// Seconds since the last keyboard/mouse/other input event in this login session.
    nonisolated static func systemIdleTime() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: CGEventType(rawValue: ~0)!
        )
    }

    // MARK: - Polling

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkIdleStatus()
            }
        }
        checkIdleStatus()
    }

    private func checkIdleStatus() {
        guard isRunning else { return }
        let idleTime = Self.systemIdleTime()
        let idleNow = idleTime >= idleThreshold
        guard idleNow != isIdle else { return }
        isIdle = idleNow

        if idleNow {
            logger.debug("User idle for \(Int(idleTime / 60)) minutes")
        } else {
            logger.debug("User became active after idle period")
        }

        Task {
            await PresenceManager.shared.handleIdleStateChange(idleNow)
        }
    }

    // MARK: - Cleanup

    func cleanup() {
        pollTimer?.invalidate()
        pollTimer = nil
        isIdle = false
        logger.debug("Idle polling stopped")
    }
}
