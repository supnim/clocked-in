import SwiftUI
import UserNotifications
import Observation
import OSLog

/// Data for displaying an in-app notification about friend activity changes
struct FriendActivityNotification: Equatable {
    let friend: FriendPresence
    let oldApp: String?
    let newApp: String?
    let oldAppIcon: Data?
    let newAppIcon: Data?
    let timestamp: Date

    static func == (lhs: FriendActivityNotification, rhs: FriendActivityNotification) -> Bool {
        lhs.friend.uid == rhs.friend.uid && lhs.timestamp == rhs.timestamp
    }
}

/// Notification type for friend joining same app
struct FriendJoinedNotification: Equatable {
    let friend: FriendPresence
    let appName: String
    let appIcon: Data?
    let timestamp: Date

    static func == (lhs: FriendJoinedNotification, rhs: FriendJoinedNotification) -> Bool {
        lhs.friend.uid == rhs.friend.uid && lhs.timestamp == rhs.timestamp
    }
}

@MainActor
@Observable
final class NotchNotificationManager {
    static let shared = NotchNotificationManager()

    /// Current notification to display in the notch (nil when no notification active)
    var currentNotification: FriendActivityNotification? = nil

    /// Current "friend joined" notification
    var joinedNotification: FriendJoinedNotification? = nil

    @ObservationIgnored
    private let center = UNUserNotificationCenter.current()
    @ObservationIgnored
    private var lastNotificationTime: Date?
    @ObservationIgnored
    private let minIntervalBetweenNotifications: TimeInterval = 3 // seconds
    @ObservationIgnored
    private var dismissTask: Task<Void, Never>?

    /// Track which friends have already triggered a join notification for current app session
    /// Key: "\(friendUid)_\(bundleId)" - reset when user switches apps
    @ObservationIgnored
    private var joinNotificationsSent: Set<String> = []

    /// Current user's app for tracking session changes
    @ObservationIgnored
    private var currentUserBundleId: String?

    private let log = Logger(subsystem: "com.clockedin", category: "NotchNotificationManager")

    private init() {
        requestNotificationPermission()
    }

    private func requestNotificationPermission() {
        center.requestAuthorization(options: [.alert, .sound]) { [self] granted, error in
            if let error = error {
                log.error("Notification permission error: \(error)")
            }
        }
    }

    func showFriendActivityChange(friend: FriendPresence, oldApp: String?, newApp: String?, oldAppIcon: Data? = nil, newAppIcon: Data? = nil) {
        // Only show if user is active (per CLAUDE.md)
        guard isUserActive() else { return }

        // Don't spam notifications
        if let lastTime = lastNotificationTime,
           Date().timeIntervalSince(lastTime) < minIntervalBetweenNotifications {
            return
        }

        // Don't notify for offline transitions
        guard friend.status != .offline else { return }

        lastNotificationTime = Date()

        // Cancel any pending dismiss task
        dismissTask?.cancel()

        // Set the observable notification for in-app display
        currentNotification = FriendActivityNotification(
            friend: friend,
            oldApp: oldApp,
            newApp: newApp,
            oldAppIcon: oldAppIcon,
            newAppIcon: newAppIcon,
            timestamp: Date()
        )

        // Auto-dismiss after 3 seconds
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self.currentNotification = nil
        }

        // Also send system notification for when app is in background
        let content = UNMutableNotificationContent()
        content.title = "\(friend.user.username) switched apps"
        content.body = formatNotificationBody(oldApp: oldApp, newApp: newApp)
        content.sound = nil // Silent per plan
        content.interruptionLevel = .passive

        let request = UNNotificationRequest(
            identifier: "friend_activity_\(friend.uid)_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        center.add(request)
    }

    /// Manually dismiss the current notification
    func dismissNotification() {
        dismissTask?.cancel()
        currentNotification = nil
        joinedNotification = nil
    }

    // MARK: - Friend Joined Same App

    /// Called when the current user switches apps - resets join notification tracking
    func updateCurrentUserApp(_ bundleId: String?) {
        guard bundleId != currentUserBundleId else { return }
        currentUserBundleId = bundleId
        // Reset notifications sent when user switches apps (new session)
        joinNotificationsSent.removeAll()
    }

    /// Clear stale join tracking when user transitions from invisible → visible
    func clearJoinNotificationTracking() {
        joinNotificationsSent.removeAll()
    }

    /// Show notification when a friend joins the same app the user is currently using
    /// Only notifies once per friend per app session (until user switches apps)
    func showFriendJoinedSameApp(friend: FriendPresence, appName: String, appIcon: Data?) {
        guard isUserActive() else { return }

        // Build tracking key for this friend + app combination
        guard let bundleId = currentUserBundleId, !bundleId.isEmpty else { return }
        let trackingKey = "\(friend.uid)_\(bundleId)"

        // Check if we already notified for this friend in this app session
        guard !joinNotificationsSent.contains(trackingKey) else { return }

        // Don't spam notifications
        if let lastTime = lastNotificationTime,
           Date().timeIntervalSince(lastTime) < minIntervalBetweenNotifications {
            return
        }

        // Mark as notified
        joinNotificationsSent.insert(trackingKey)
        lastNotificationTime = Date()

        // Cancel any pending dismiss task
        dismissTask?.cancel()

        // Set the observable notification for in-app display
        joinedNotification = FriendJoinedNotification(
            friend: friend,
            appName: appName,
            appIcon: appIcon,
            timestamp: Date()
        )

        // Auto-dismiss after 4 seconds (slightly longer for this special notification)
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self.joinedNotification = nil
        }

        // Also send system notification
        let content = UNMutableNotificationContent()
        content.title = "\(friend.user.name) joined you"
        content.body = "You're both in \(appName)"
        content.sound = UNNotificationSound.default // Use sound for this special moment
        content.interruptionLevel = .active

        let request = UNNotificationRequest(
            identifier: "friend_joined_\(friend.uid)_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        center.add(request)
    }

    /// Check if a friend is in the same app as the current user
    func isFriendInSameApp(_ friendBundleId: String?) -> Bool {
        guard let friendBundleId, !friendBundleId.isEmpty,
              let userBundleId = currentUserBundleId, !userBundleId.isEmpty else {
            return false
        }
        return friendBundleId == userBundleId
    }

    private func formatNotificationBody(oldApp: String?, newApp: String?) -> String {
        if let old = oldApp, let new = newApp {
            return "\(old) → \(new)"
        } else if let new = newApp {
            return "Now using \(new)"
        } else {
            return "Activity changed"
        }
    }

    private func isUserActive() -> Bool {
        return IdleDetector.shared.isUserActive
    }
}