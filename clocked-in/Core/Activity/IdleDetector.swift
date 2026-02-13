import Foundation
import AppKit
import OSLog

@MainActor
@Observable
final class IdleDetector {
    static let shared = IdleDetector()

    private let logger = Logger(subsystem: "com.clockedin", category: "IdleDetector")

    private var lastActivityTime: Date = Date()
    private var idleTimer: Timer?
    private let idleThreshold: TimeInterval = 15 * 60 // 15 minutes

    // Event monitors
    private var mouseMonitor: Any?
    private var keyboardMonitor: Any?
    private var localMonitor: Any?

    @ObservationIgnored
    private var isRunning = false

    private init() {
        // Don't start automatically - wait for explicit start() call
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        lastActivityTime = Date()
        setupActivityMonitoring()
        startIdleTimer()
        logger.debug("IdleDetector started")
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        cleanup()
        logger.debug("IdleDetector stopped")
    }

    nonisolated deinit {
        // Deinit is nonisolated - event monitors and timer will be cleaned up when deallocated
    }

    var isUserActive: Bool {
        Date().timeIntervalSince(lastActivityTime) < idleThreshold
    }

    var timeSinceLastActivity: TimeInterval {
        Date().timeIntervalSince(lastActivityTime)
    }

    // MARK: - Activity Monitoring

    private func setupActivityMonitoring() {
        // Monitor mouse events
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.handleUserActivity()
        }

        // Monitor keyboard events
        keyboardMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] _ in
            self?.handleUserActivity()
        }

        // Also monitor local events (when app is active)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            self?.handleUserActivity()
            return event // Pass through
        }

        logger.debug("Activity monitoring started")
    }

    private func handleUserActivity() {
        // Check if we were idle BEFORE updating lastActivityTime
        let wasIdle = !isUserActive

        lastActivityTime = Date()

        // If we were idle, notify that user is now active
        if wasIdle {
            logger.debug("User became active after idle period")
            Task {
                await PresenceManager.shared.handleIdleStateChange(false)
            }
        }
    }

    // MARK: - Idle Timer

    private func startIdleTimer() {
        idleTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { await self?.checkIdleStatus() }
        }
    }

    private func checkIdleStatus() async {
        let timeSinceActivity = Date().timeIntervalSince(lastActivityTime)

        if timeSinceActivity >= idleThreshold {
            logger.debug("User idle for \(Int(timeSinceActivity / 60)) minutes")
            await PresenceManager.shared.handleIdleStateChange(true)
        }
    }

    // MARK: - Cleanup

    func cleanup() {
        // Invalidate timer
        idleTimer?.invalidate()
        idleTimer = nil

        // Remove event monitors
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }

        if let keyboardMonitor {
            NSEvent.removeMonitor(keyboardMonitor)
            self.keyboardMonitor = nil
        }

        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }

        logger.debug("Activity monitoring stopped")
    }

}