import Foundation
import Observation

// MARK: - Presence Payload (pure, unit tested)

/// What the client sends in `{"type":"presence_update","data":{...}}`.
/// Privacy rules live here so they apply on every path (active, idle, reconnect):
/// - hidden app → status "ghost", no app fields
/// - window title / browser domain are never sent (v1 App Store build)
/// - icons whose base64 exceeds 16 KB are dropped
struct PresencePayload: Equatable {
    enum Status: String {
        case online
        case away
        case ghost
    }

    /// Max base64 icon length the client will send (server limit is 24000 chars)
    static let maxIconBase64Length = 16 * 1024

    let status: Status
    let appName: String?
    let bundleId: String?
    /// Base64-encoded PNG
    let appIcon: String?

    static let ghost = PresencePayload(status: .ghost, appName: nil, bundleId: nil, appIcon: nil)

    /// Builds the payload for the user's current activity.
    /// - Parameters:
    ///   - activity: Latest frontmost-app activity (nil if unknown)
    ///   - isIdle: Whether the user is idle (→ "away")
    ///   - hiddenApps: Bundle IDs the user hid; these always produce "ghost"
    static func make(activity: Activity?, isIdle: Bool, hiddenApps: [String]) -> PresencePayload {
        if let activity, !activity.bundleId.isEmpty, hiddenApps.contains(activity.bundleId) {
            return .ghost
        }

        let status: Status = isIdle ? .away : .online

        guard let activity, !activity.bundleId.isEmpty || !activity.appName.isEmpty else {
            return PresencePayload(status: status, appName: nil, bundleId: nil, appIcon: nil)
        }

        let icon: String? = activity.appIcon.flatMap { data in
            let base64 = data.base64EncodedString()
            return base64.count <= maxIconBase64Length ? base64 : nil
        }

        return PresencePayload(
            status: status,
            appName: activity.appName.isEmpty ? nil : String(activity.appName.prefix(100)),
            bundleId: activity.bundleId.isEmpty ? nil : String(activity.bundleId.prefix(255)),
            appIcon: icon
        )
    }

    /// `data` dictionary sent to the server. Only contract keys; nil fields omitted.
    func dataDictionary() -> [String: Any] {
        var data: [String: Any] = ["status": status.rawValue]
        if let appName { data["app_name"] = appName }
        if let bundleId { data["bundle_id"] = bundleId }
        if let appIcon { data["app_icon"] = appIcon }
        return data
    }

    /// Full WebSocket message
    func message() -> [String: Any] {
        ["type": "presence_update", "data": dataDictionary()]
    }
}

// MARK: - Presence Manager

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

    /// Set when an update couldn't be sent while offline. On reconnect the *current*
    /// state is sent (not the stale queued one).
    @ObservationIgnored
    private var pendingUpdate: PresencePayload?

    /// Whether there is a pending update waiting to be sent
    var hasPendingUpdates: Bool {
        pendingUpdate != nil
    }

    private init() {}

    /// The payload that represents the user's presence right now.
    func currentPayload() -> PresencePayload {
        PresencePayload.make(
            activity: lastActivity,
            isIdle: isIdle,
            hiddenApps: AppSettings.shared.hiddenApps
        )
    }

    // MARK: - Activity Integration

    func updatePresence(for activity: Activity) async {
        // Store for idle recovery and UI
        lastActivity = activity
        currentActivity = activity

        // Update notification manager with current app (for join notifications)
        await NotchNotificationManager.shared.updateCurrentUserApp(activity.bundleId)

        // Invisible: share nothing (go_offline was sent when invisible mode was enabled)
        guard !AppSettings.shared.isInvisible else {
            pendingUpdate = nil
            return
        }

        // Send immediately (ActivityMonitor already debounces)
        await publishCurrentPresence()
    }

    /// Sends the current presence, or queues it if the socket is down.
    private func publishCurrentPresence() async {
        guard !AppSettings.shared.isInvisible else {
            pendingUpdate = nil
            return
        }

        let payload = currentPayload()
        guard WebSocketClient.shared.isConnected else {
            pendingUpdate = payload
            return
        }

        pendingUpdate = nil
        await WebSocketClient.shared.sendPresence(payload)
    }

    // MARK: - Connection Events

    /// Called by WebSocketClient whenever a (re)connection is established.
    /// Re-asserts our presence (the server forgets it when the old socket closed),
    /// or re-sends go_offline when invisible.
    func connectionDidOpen() async {
        if AppSettings.shared.isInvisible {
            pendingUpdate = nil
            await WebSocketClient.shared.sendGoOffline()
            return
        }
        guard lastActivity != nil || pendingUpdate != nil else { return }
        await publishCurrentPresence()
    }

    // MARK: - Pending Updates Queue

    /// Flush pending update when reconnecting
    func flushPendingUpdates() async {
        guard WebSocketClient.shared.isConnected else { return }
        guard pendingUpdate != nil else { return }
        await publishCurrentPresence()
    }

    /// Clear pending updates (e.g., when user goes invisible)
    func clearPendingUpdates() {
        pendingUpdate = nil
    }

    // MARK: - Invisible Mode

    /// Called by AppSettings when `isInvisible` changes.
    /// - Invisible on: drop queued updates and tell the server to remove our presence.
    ///   The socket stays open so friends' presence keeps streaming to us.
    /// - Invisible off: reconnect if needed and re-send current presence.
    func handleInvisibleModeChanged(_ invisible: Bool) async {
        if invisible {
            pendingUpdate = nil
            await WebSocketClient.shared.sendGoOffline()
        } else if WebSocketClient.shared.isConnected {
            await publishCurrentPresence()
        } else {
            // connectionDidOpen() will send presence once connected
            WebSocketClient.shared.reconnect()
        }
    }

    // MARK: - Connection Management

    func startPresence() {
        // WebSocket connection is managed by WebSocketClient
        // This method exists for API compatibility
        // Connection should be established via WebSocketClient.shared.connect(token:)
    }

    func stopPresence() {
        pendingUpdate = nil
        Task {
            await setOffline()
        }
    }

    /// Removes our presence on the server immediately (friends see us offline).
    func setOffline() async {
        pendingUpdate = nil
        guard WebSocketClient.shared.isConnected else { return }
        await WebSocketClient.shared.sendGoOffline()
    }

    // MARK: - Idle State Handling

    func handleIdleStateChange(_ idle: Bool) async {
        guard idle != isIdle else { return }
        isIdle = idle

        // Invisible: track state but share nothing
        guard !AppSettings.shared.isInvisible else { return }

        // Same privacy filtering as the active path (hidden app → ghost)
        await publishCurrentPresence()
    }
}
