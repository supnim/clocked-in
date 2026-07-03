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

    func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        cleanupTimer?.invalidate()
        cleanupTimer = nil

        let notificationCenter = NSWorkspace.shared.notificationCenter
        if let sleepObserver {
            notificationCenter.removeObserver(sleepObserver)
            self.sleepObserver = nil
        }
        if let wakeObserver {
            notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        if let terminateObserver {
            notificationCenter.removeObserver(terminateObserver)
            self.terminateObserver = nil
        }
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

    private let sessionsKey = "com.clockedin.activity_sessions"

    private func saveSession(_ session: ActivitySession) async {
        // Persist locally via UserDefaults
        var sessions = loadLocalSessions()
        sessions.append(session)
        // Keep only last 100 sessions locally
        if sessions.count > 100 {
            sessions = Array(sessions.suffix(100))
        }
        if let data = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(data, forKey: sessionsKey)
        }

        logger.debug("Saved session locally: \(session.appName) (\(session.duration)s)")
    }

    private func loadLocalSessions() -> [ActivitySession] {
        guard let data = UserDefaults.standard.data(forKey: sessionsKey),
              let sessions = try? JSONDecoder().decode([ActivitySession].self, from: data) else {
            return []
        }
        return sessions
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

        var sessions = loadLocalSessions()
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60) // 24 hours ago
        var cleaned = 0

        for i in 0..<sessions.count {
            if sessions[i].endTime == nil && sessions[i].startTime < cutoff {
                // Close orphan: set endTime to startTime + 1 hour
                sessions[i].endTime = sessions[i].startTime.addingTimeInterval(3600)
                cleaned += 1
            }
        }

        if cleaned > 0 {
            if let data = try? JSONEncoder().encode(sessions) {
                UserDefaults.standard.set(data, forKey: sessionsKey)
            }
            logger.debug("Cleaned up \(cleaned) orphan sessions")
        }
    }
}