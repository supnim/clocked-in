import Foundation
import AppKit
import OSLog

@MainActor
@Observable
final class ActivitySessionManager {
    static let shared = ActivitySessionManager()

    private let logger = Logger(subsystem: "com.clockedin", category: "ActivitySessionManager")

    private var currentSession: ActivitySession?
    private var debounceTask: Task<Void, Never>?

    // System event observers
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var terminateObserver: NSObjectProtocol?
    private var cleanupTimer: Timer?

    private init() {
        setupSystemObservers()
        setupOrphanCleanup()
    }

    nonisolated deinit {
        // Deinit is nonisolated - observers and tasks will be cleaned up when deallocated
    }

    // MARK: - Session Management

    func handleActivityChange(_ activity: Activity) async {
        // Cancel previous debounce
        debounceTask?.cancel()

        debounceTask = Task {
            try? await Task.sleep(for: .seconds(2)) // 2s debounce
            guard !Task.isCancelled else { return }

            await closeCurrentSession()
            await startNewSession(with: activity)
        }
    }

    private func startNewSession(with activity: Activity) async {
        let session = ActivitySession(
            appName: activity.appName,
            bundleId: activity.bundleId,
            startTime: activity.timestamp,
            windowTitles: activity.windowTitle.map { [$0] },
            browserDomains: activity.browserDomain.map { [$0] }
        )

        currentSession = session
        logger.debug("Started session: \(session.appName) (\(session.bundleId))")

        // TODO: Update presence in Realtime DB
        // await PresenceManager.shared.updatePresence(for: activity)
    }

    private func closeCurrentSession() async {
        guard let session = currentSession else { return }

        let endTime = Date()
        var closedSession = session
        closedSession.endTime = endTime

        currentSession = nil
        logger.debug("Closed session: \(session.appName) after \(session.duration) seconds")

        // Save to Firestore
        await saveSession(closedSession)
    }

    // MARK: - System Events

    private func setupSystemObservers() {
        let notificationCenter = NSWorkspace.shared.notificationCenter

        // Sleep notification
        sleepObserver = notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { await self?.handleSystemSleep() }
        }

        // Wake notification
        wakeObserver = notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { await self?.handleSystemWake() }
        }

        // App termination
        terminateObserver = notificationCenter.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { await self?.handleAppTermination() }
        }
    }

    private func handleSystemSleep() async {
        logger.debug("System sleeping, closing current session")
        await closeCurrentSession()
    }

    private func handleSystemWake() async {
        logger.debug("System woke, will start new session on next app switch")
        // Don't start a session here - wait for next app activation
    }

    private func handleAppTermination() async {
        logger.debug("App terminating, closing current session")
        cleanupTimer?.invalidate()
        cleanupTimer = nil
        await closeCurrentSession()
    }

    // MARK: - Persistence

    private func saveSession(_ session: ActivitySession) async {
        // Generate session ID
        let sessionId = UUID().uuidString

        // TODO: Save to backend
        // try await ActivityService.shared.saveSession(session, id: sessionId)

        logger.debug("Saved session to backend: \(sessionId)")
    }

    // MARK: - Orphan Cleanup

    private func setupOrphanCleanup() {
        Task {
            // Run cleanup on app launch
            await cleanupOrphanSessions()

            // Schedule periodic cleanup (daily) - use weak self to prevent retain cycle
            cleanupTimer = Timer.scheduledTimer(withTimeInterval: 86400, repeats: true) { [weak self] _ in
                Task { [weak self] in
                    await self?.cleanupOrphanSessions()
                }
            }
        }
    }

    // MARK: - Integration with ActivityMonitor

    func connectToActivityMonitor(_ activityMonitor: ActivityMonitor) {
        // Connect activity changes to session management
        // This would be called during app setup
    }

    private func cleanupOrphanSessions() async {
        logger.debug("Checking for orphan sessions to clean up")

        // TODO: Query backend for sessions without endTime older than 24h
        // let orphans = try await ActivityService.shared.findOrphanSessions()

        // For each orphan, set endTime to startTime + 1 hour
        // try await ActivityService.shared.closeOrphanSessions(orphans)

        logger.debug("Cleaned up orphan sessions")
    }
}