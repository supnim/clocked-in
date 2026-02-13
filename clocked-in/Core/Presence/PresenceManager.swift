import Foundation
import Observation

@MainActor
@Observable
final class PresenceManager {
    static let shared = PresenceManager()

    var isConnected: Bool {
        WebSocketClient.shared.isConnected
    }

    var isReconnecting: Bool {
        WebSocketClient.shared.isReconnecting
    }

    @ObservationIgnored
    private var isIdle = false

    /// Current user's activity (exposed for UI to compare with friends)
    var currentActivity: Activity?

    @ObservationIgnored
    private var lastActivity: Activity?

    // MARK: - Offline Update Queue

    /// Pending presence updates queued while offline
    @ObservationIgnored
    private var pendingUpdates: [Activity] = []

    /// Maximum number of pending updates to keep (prevent memory issues)
    private let maxPendingUpdates = 10

    /// Whether there are pending updates waiting to be sent
    var hasPendingUpdates: Bool {
        !pendingUpdates.isEmpty
    }

    /// Number of pending updates
    var pendingUpdateCount: Int {
        pendingUpdates.count
    }

    private init() {}

    // MARK: - Activity Integration (Updated for WebSocket)

    func updatePresence(for activity: Activity) async {
        // Store for idle recovery and UI
        lastActivity = activity
        currentActivity = activity

        // Update notification manager with current app (for join notifications)
        await NotchNotificationManager.shared.updateCurrentUserApp(activity.bundleId)

        // Check invisible mode first - don't send any presence
        guard !AppSettings.shared.isInvisible else {
            await setOffline()
            return
        }

        // If user is idle, don't update presence (keep showing away)
        guard !isIdle else { return }

        // Send presence update immediately (ActivityMonitor already debounces)
        await sendPresenceUpdate(for: activity)
    }

    private func sendPresenceUpdate(for activity: Activity) async {
        // Queue update if offline
        guard WebSocketClient.shared.isConnected else {
            queuePendingUpdate(activity)
            return
        }

        // Check if app is hidden (ghost mode) - privacy-first approach
        if AppSettings.shared.hiddenApps.contains(activity.bundleId) {
            await sendGhostPresence()
            return
        }

        // Build activity with privacy filtering applied
        let filteredActivity = Activity(
            appName: activity.appName,
            bundleId: activity.bundleId,
            windowTitle: AppSettings.shared.shareWindowTitle ? activity.windowTitle : nil,
            browserDomain: AppSettings.shared.shareBrowserURL ? activity.browserDomain : nil,
            appIcon: activity.appIcon
        )

        await WebSocketClient.shared.sendPresenceUpdate(filteredActivity, status: "online")
    }

    // MARK: - Pending Updates Queue

    private func queuePendingUpdate(_ activity: Activity) {
        // Only keep the most recent update for efficiency
        // When we come back online, we only need to send current state
        pendingUpdates = [activity]
    }

    /// Flush pending updates when reconnecting
    /// Called by NetworkMonitor when connection is restored
    func flushPendingUpdates() async {
        guard WebSocketClient.shared.isConnected else { return }
        guard !pendingUpdates.isEmpty else { return }

        // Send only the most recent activity (last state)
        if let latestActivity = pendingUpdates.last {
            await sendPresenceUpdate(for: latestActivity)
        }

        pendingUpdates.removeAll()
    }

    /// Clear pending updates (e.g., when user goes invisible)
    func clearPendingUpdates() {
        pendingUpdates.removeAll()
    }

    private func sendGhostPresence() async {
        guard WebSocketClient.shared.isConnected else { return }

        // Send ghost status with no activity details
        let emptyActivity = Activity(
            appName: "",
            bundleId: "",
            windowTitle: nil,
            browserDomain: nil,
            appIcon: nil
        )
        await WebSocketClient.shared.sendPresenceUpdate(emptyActivity, status: "ghost")
    }

    // MARK: - Connection Management

    func startPresence() {
        // WebSocket connection is managed by WebSocketClient
        // This method exists for API compatibility
        // Connection should be established via WebSocketClient.shared.connect(token:)
    }

    func stopPresence() {
        Task {
            await setOffline()
        }
    }

    func setOffline() async {
        guard WebSocketClient.shared.isConnected else { return }

        let emptyActivity = Activity(
            appName: "",
            bundleId: "",
            windowTitle: nil,
            browserDomain: nil,
            appIcon: nil
        )
        await WebSocketClient.shared.sendPresenceUpdate(emptyActivity, status: "offline")
    }

    // MARK: - Idle State Handling

    func handleIdleStateChange(_ idle: Bool) async {
        // Skip if invisible mode
        guard !AppSettings.shared.isInvisible else { return }

        isIdle = idle

        if idle {
            // User became idle - send away status
            await setAway()
        } else {
            // User became active - restore online status with last activity
            if let activity = lastActivity {
                await sendPresenceUpdate(for: activity)
            }
        }
    }

    private func setAway() async {
        guard WebSocketClient.shared.isConnected else { return }

        // Send away status - keep activity info but mark as away
        let activity = lastActivity ?? Activity(
            appName: "",
            bundleId: "",
            windowTitle: nil,
            browserDomain: nil,
            appIcon: nil
        )

        // Apply privacy filtering if we have an activity
        if let lastActivity, !AppSettings.shared.hiddenApps.contains(lastActivity.bundleId) {
            let filteredActivity = Activity(
                appName: lastActivity.appName,
                bundleId: lastActivity.bundleId,
                windowTitle: AppSettings.shared.shareWindowTitle ? lastActivity.windowTitle : nil,
                browserDomain: AppSettings.shared.shareBrowserURL ? lastActivity.browserDomain : nil,
                appIcon: lastActivity.appIcon
            )
            await WebSocketClient.shared.sendPresenceUpdate(filteredActivity, status: "away")
        } else {
            await WebSocketClient.shared.sendPresenceUpdate(activity, status: "away")
        }
    }
}
