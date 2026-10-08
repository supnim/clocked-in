import Foundation

struct FriendPresence: Identifiable, Hashable {
    static func == (lhs: FriendPresence, rhs: FriendPresence) -> Bool {
        lhs.uid == rhs.uid
            && lhs.isOnline == rhs.isOnline
            && lhs.serverStatus == rhs.serverStatus
            && lhs.lastSeen == rhs.lastSeen
            && lhs.currentActivity == rhs.currentActivity
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(uid)
        hasher.combine(isOnline)
        hasher.combine(serverStatus)
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
    /// Status reported by the server ("online" | "away" | "ghost" | "offline").
    /// Nil for legacy/cached entries, in which case `isOnline` decides.
    var serverStatus: PresenceStatus? = nil

    /// Display status: the server's `status` field, falling back to the `online` flag.
    var status: PresenceStatus {
        if !isOnline { return .offline }
        if let serverStatus { return serverStatus }
        return .online
    }

    init(
        uid: String,
        user: User,
        isOnline: Bool = false,
        lastSeen: Date = Date(),
        currentActivity: Activity? = nil,
        currentlyWith: [String]? = nil,
        serverStatus: PresenceStatus? = nil
    ) {
        self.uid = uid
        self.user = user
        self.isOnline = isOnline
        self.lastSeen = lastSeen
        self.currentActivity = currentActivity
        self.currentlyWith = currentlyWith
        self.serverStatus = serverStatus
    }
}

enum PresenceStatus: String, Codable {
    case online   // 🟢 Active
    case away     // 🟡 Idle 15+ min, app still running
    case offline  // ⚫ App closed / disconnected / invisible
    case ghost    // 🐙 Using hidden app (online, app details withheld)
}
