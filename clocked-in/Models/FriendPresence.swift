import Foundation

struct FriendPresence: Identifiable, Hashable {
    static func == (lhs: FriendPresence, rhs: FriendPresence) -> Bool {
        lhs.uid == rhs.uid && lhs.isOnline == rhs.isOnline && lhs.lastSeen == rhs.lastSeen && lhs.currentActivity == rhs.currentActivity
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(uid)
        hasher.combine(isOnline)
        hasher.combine(lastSeen)
        hasher.combine(currentActivity)
    }
    var id: String { uid }
    var uid: String
    var user: User
    var isOnline: Bool
    var lastSeen: Date
    var currentActivity: Activity?
    var currentlyWith: [String]?    // Usernames of friends in same app

    var status: PresenceStatus {
        if !isOnline { return .offline }
        guard let activity = currentActivity else { return .away }
        let minutesAgo = Date().timeIntervalSince(activity.timestamp) / 60
        return minutesAgo < 15 ? .online : .away
    }

    init(uid: String, user: User, isOnline: Bool = false, lastSeen: Date = Date(), currentActivity: Activity? = nil, currentlyWith: [String]? = nil) {
        self.uid = uid
        self.user = user
        self.isOnline = isOnline
        self.lastSeen = lastSeen
        self.currentActivity = currentActivity
        self.currentlyWith = currentlyWith
    }
}

enum PresenceStatus: String, Codable {
    case online   // 🟢 Active in last 15 min
    case away     // 🟡 Idle 15+ min, app still running
    case offline  // ⚫ App closed / disconnected
    case ghost    // 🐙 Using hidden app
}