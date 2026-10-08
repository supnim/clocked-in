import Foundation
import Observation

// Protocol for types that provide activity data
protocol ActivityDataProvider {
    var appName: String? { get }
    var bundleId: String? { get }
    var windowTitle: String? { get }
    var browserDomain: String? { get }
    var appIconB64: String? { get }
    var updatedAt: Int64? { get }
}

// Protocol for types that provide user data
protocol UserDataProvider {
    var user: PresenceUserData? { get }
}

// PresenceUpdate is a typealias of FriendPresenceData
extension FriendPresenceData: ActivityDataProvider, UserDataProvider {}

@MainActor
@Observable
final class PresenceListener {
    static let shared = PresenceListener()

    var friendsPresence: [FriendPresence] = []

    var onlineFriends: [FriendPresence] {
        friendsPresence.filter { $0.status != .offline }
    }

    var offlineFriends: [FriendPresence] {
        friendsPresence.filter { $0.status == .offline }
    }

    @ObservationIgnored
    private var userCache: [String: User] = [:]

    @ObservationIgnored
    private var listenerCount = 0

    private init() {}

    func startListening() {
        listenerCount += 1
        guard listenerCount == 1 else { return }

        // NOTE: invisible mode only hides *our* presence from friends; we still
        // show friends' presence to the user, so always listen.

        // Load cached friends for immediate display
        if friendsPresence.isEmpty, let cachedFriends = CachedFriendsService.shared.loadCachedFriends() {
            self.friendsPresence = cachedFriends
            // Populate user cache from cached friends
            for friend in cachedFriends {
                userCache[friend.uid] = friend.user
            }
        }

        // Set up WebSocket callbacks
        setupWebSocketCallbacks()

        // Apply an initial_presence that arrived before we attached
        if let initial = WebSocketClient.shared.latestInitialPresence {
            handleInitialPresence(initial)
        }
    }

    func stopListening() {
        listenerCount = max(0, listenerCount - 1)
        guard listenerCount == 0 else { return }
        // Clear callbacks
        WebSocketClient.shared.onInitialPresence = nil
        WebSocketClient.shared.onPresenceUpdate = nil
        WebSocketClient.shared.onNudge = nil
        WebSocketClient.shared.onFriendRequest = nil
        // Clear cached state
        clearCache()
    }

    func clearCache() {
        userCache.removeAll()
        friendsPresence.removeAll()
    }

    // MARK: - WebSocket Callbacks

    private func setupWebSocketCallbacks() {
        // Handle initial presence (full friend list on connect)
        // (WebSocketClient invokes callbacks on the MainActor, in order — handle synchronously
        // so an initial_presence can't be applied after a later presence_update.)
        WebSocketClient.shared.onInitialPresence = { [weak self] presences in
            self?.handleInitialPresence(presences)
        }

        // Handle individual presence updates
        WebSocketClient.shared.onPresenceUpdate = { [weak self] update in
            self?.handlePresenceUpdate(update)
        }

        // Handle nudges
        WebSocketClient.shared.onNudge = { nudge in
            Task { @MainActor in
                let username = nudge.fromUsername ?? "Someone"
                NudgeEffects.shared.playNudge(from: username)
            }
        }
    }

    private func handleInitialPresence(_ presences: [FriendPresenceData]) {
        var newFriendsPresence: [FriendPresence] = []

        for data in presences {
            let user = resolveUser(uid: data.userId, from: data)
            let activity = buildActivity(from: data)

            let friendPresence = FriendPresence(
                uid: data.userId,
                user: user,
                isOnline: data.online ?? false,
                lastSeen: Date(timeIntervalSince1970: Double(data.lastSeen ?? data.updatedAt ?? 0) / 1000),
                currentActivity: activity,
                serverStatus: data.presenceStatus
            )

            newFriendsPresence.append(friendPresence)
        }

        self.friendsPresence = newFriendsPresence
        updateCurrentlyWith()
        CachedFriendsService.shared.cacheFriendsList(friendsPresence)
    }

    private func handlePresenceUpdate(_ update: PresenceUpdate) {
        let uid = update.userId
        let user = resolveUser(uid: uid, from: update)
        let activity = buildActivity(from: update)

        let friendPresence = FriendPresence(
            uid: uid,
            user: user,
            isOnline: update.online ?? false,
            lastSeen: Date(timeIntervalSince1970: Double(update.updatedAt ?? 0) / 1000),
            currentActivity: activity,
            serverStatus: update.presenceStatus
        )

        // Get old activity for notification comparison
        let oldActivity = friendsPresence.first(where: { $0.uid == uid })?.currentActivity

        // Update or add to array
        if let index = friendsPresence.firstIndex(where: { $0.uid == uid }) {
            friendsPresence[index] = friendPresence
        } else {
            friendsPresence.append(friendPresence)
        }

        updateCurrentlyWith()
        CachedFriendsService.shared.cacheFriendsList(friendsPresence)

        // Show notification for activity changes
        if let oldActivity = oldActivity,
           let newActivity = activity,
           oldActivity.bundleId != newActivity.bundleId {
            if isUserActiveForNotifications() {
                Task { @MainActor in
                    // Check if friend just joined the same app as user
                    if NotchNotificationManager.shared.isFriendInSameApp(newActivity.bundleId) {
                        // Show special "joined you" notification
                        await NotchNotificationManager.shared.showFriendJoinedSameApp(
                            friend: friendPresence,
                            appName: newActivity.appName,
                            appIcon: newActivity.appIcon
                        )
                    } else {
                        // Regular activity change notification
                        await NotchNotificationManager.shared.showFriendActivityChange(
                            friend: friendPresence,
                            oldApp: oldActivity.appName,
                            newApp: newActivity.appName,
                            oldAppIcon: oldActivity.appIcon,
                            newAppIcon: newActivity.appIcon
                        )
                    }
                }
            }
        }
    }

    // MARK: - Activity Building

    private func buildActivity(from provider: ActivityDataProvider) -> Activity? {
        guard let appName = provider.appName, !appName.isEmpty else { return nil }

        let appIconData: Data? = {
            guard let iconBase64 = provider.appIconB64, !iconBase64.isEmpty else { return nil }
            return Data(base64Encoded: iconBase64)
        }()

        return Activity(
            appName: appName,
            bundleId: provider.bundleId ?? "",
            // v1: window titles / browser domains are never shared
            windowTitle: nil,
            browserDomain: nil,
            appIcon: appIconData,
            timestamp: Date(timeIntervalSince1970: Double(provider.updatedAt ?? Int64(Date().timeIntervalSince1970 * 1000)) / 1000)
        )
    }

    // MARK: - User Building

    private func resolveUser(uid: String, from provider: UserDataProvider) -> User {
        if let userData = provider.user {
            let user = User(
                id: uid,
                username: userData.username,
                displayName: userData.displayName,
                avatarUrl: userData.avatarUrl,
                statusMessage: userData.statusMessage
            )
            userCache[uid] = user
            return user
        } else if let cachedUser = userCache[uid] {
            return cachedUser
        } else {
            let user = User(id: uid, username: "user_\(uid.prefix(6))")
            userCache[uid] = user
            return user
        }
    }

    // MARK: - Notifications

    private func isUserActiveForNotifications() -> Bool {
        return IdleDetector.shared.isUserActive
    }

    // MARK: - Currently With Detection

    private func updateCurrentlyWith() {
        // Group friends by app bundle ID
        var appToFriends: [String: [FriendPresence]] = [:]

        for friend in friendsPresence.filter({ $0.isOnline }) {
            if let bundleId = friend.currentActivity?.bundleId {
                appToFriends[bundleId, default: []].append(friend)
            }
        }

        // Update currentlyWith for each friend
        for i in 0..<friendsPresence.count {
            let friend = friendsPresence[i]
            if let bundleId = friend.currentActivity?.bundleId,
               let friendsInSameApp = appToFriends[bundleId],
               friendsInSameApp.count > 1 {
                // Find other friends in the same app (exclude self)
                let others = friendsInSameApp.filter { $0.uid != friend.uid }
                friendsPresence[i].currentlyWith = others.map { $0.user.username }
            } else {
                friendsPresence[i].currentlyWith = nil
            }
        }
    }

    // MARK: - User Cache Management

    func updateUserCache(userId: String, user: User) {
        userCache[userId] = user
        // Update any existing friend presence with new user info
        if let index = friendsPresence.firstIndex(where: { $0.uid == userId }) {
            friendsPresence[index] = FriendPresence(
                uid: userId,
                user: user,
                isOnline: friendsPresence[index].isOnline,
                lastSeen: friendsPresence[index].lastSeen,
                currentActivity: friendsPresence[index].currentActivity,
                currentlyWith: friendsPresence[index].currentlyWith,
                serverStatus: friendsPresence[index].serverStatus
            )
        }
    }
}
