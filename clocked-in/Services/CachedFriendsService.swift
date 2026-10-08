import Foundation
import OSLog

/// Wrapper for cached data with timestamp
struct CachedData<T: Codable>: Codable {
    let data: T
    let cachedAt: Date

    var age: TimeInterval {
        Date().timeIntervalSince(cachedAt)
    }

    /// Human-readable time since cache was updated
    var ageDescription: String {
        let minutes = Int(age / 60)
        if minutes < 1 {
            return "just now"
        } else if minutes < 60 {
            return "\(minutes) min ago"
        } else {
            let hours = minutes / 60
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        }
    }
}

/// Cached user profile for offline display
struct CachedUserProfile: Codable {
    let user: User
    let pendingRequestsCount: Int
    let cachedAt: Date
}

@MainActor
@Observable
final class CachedFriendsService {
    static let shared = CachedFriendsService()

    // MARK: - Cache Keys
    private enum Keys {
        static let friends = "cached_friends_v2"
        static let userProfile = "cached_user_profile"
        static let lastOnlineTimestamp = "last_online_timestamp"
    }

    private let log = Logger(subsystem: "com.clockedin", category: "CachedFriendsService")
    private let userDefaults = UserDefaults.standard

    /// When the cache was last updated (nil if no cache)
    var lastUpdated: Date? {
        loadFriendsCache()?.cachedAt
    }

    /// Human-readable cache age
    var lastUpdatedDescription: String? {
        loadFriendsCache()?.ageDescription
    }

    private init() {}

    // MARK: - Friends List Caching

    func cacheFriendsList(_ friends: [FriendPresence]) {
        let cached = CachedData(data: friends, cachedAt: Date())
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(cached)
            userDefaults.set(data, forKey: Keys.friends)
            // Update last online timestamp when we successfully cache while online
            userDefaults.set(Date(), forKey: Keys.lastOnlineTimestamp)
        } catch {
            log.error("Failed to cache friends list: \(error)")
        }
    }

    func loadCachedFriends() -> [FriendPresence]? {
        loadFriendsCache()?.data
    }

    private func loadFriendsCache() -> CachedData<[FriendPresence]>? {
        guard let data = userDefaults.data(forKey: Keys.friends) else {
            return nil
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(CachedData<[FriendPresence]>.self, from: data)
        } catch {
            log.error("Failed to load cached friends (removing corrupt cache): \(error)")
            userDefaults.removeObject(forKey: Keys.friends)
            return nil
        }
    }

    // MARK: - User Profile Caching

    func cacheUserProfile(_ user: User, pendingRequestsCount: Int) {
        let cached = CachedUserProfile(
            user: user,
            pendingRequestsCount: pendingRequestsCount,
            cachedAt: Date()
        )
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(cached)
            userDefaults.set(data, forKey: Keys.userProfile)
        } catch {
            log.error("Failed to cache user profile: \(error)")
        }
    }

    func loadCachedUserProfile() -> CachedUserProfile? {
        guard let data = userDefaults.data(forKey: Keys.userProfile) else {
            return nil
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(CachedUserProfile.self, from: data)
        } catch {
            log.error("Failed to load cached user profile (removing corrupt cache): \(error)")
            userDefaults.removeObject(forKey: Keys.userProfile)
            return nil
        }
    }

    // MARK: - Online Timestamp

    /// When the app was last successfully online
    var lastOnlineTimestamp: Date? {
        userDefaults.object(forKey: Keys.lastOnlineTimestamp) as? Date
    }

    /// Mark that we're currently online (updates timestamp)
    func markOnline() {
        userDefaults.set(Date(), forKey: Keys.lastOnlineTimestamp)
    }

    // MARK: - Cache Management

    func clearCache() {
        userDefaults.removeObject(forKey: Keys.friends)
        userDefaults.removeObject(forKey: Keys.userProfile)
        // Keep lastOnlineTimestamp for analytics
    }

    /// Check if cache is stale (older than specified interval)
    func isCacheStale(olderThan interval: TimeInterval = 3600) -> Bool {
        guard let cache = loadFriendsCache() else { return true }
        return cache.age > interval
    }
}

// Extension to make FriendPresence codable for caching
extension FriendPresence: Codable {
    enum CodingKeys: String, CodingKey {
        case uid, user, isOnline, lastSeen, currentActivity, currentlyWith
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uid = try container.decode(String.self, forKey: .uid)
        user = try container.decode(User.self, forKey: .user)
        isOnline = try container.decode(Bool.self, forKey: .isOnline)
        lastSeen = try container.decode(Date.self, forKey: .lastSeen)
        currentActivity = try container.decodeIfPresent(Activity.self, forKey: .currentActivity)
        currentlyWith = try container.decodeIfPresent([String].self, forKey: .currentlyWith)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(uid, forKey: .uid)
        try container.encode(user, forKey: .user)
        try container.encode(isOnline, forKey: .isOnline)
        try container.encode(lastSeen, forKey: .lastSeen)
        try container.encodeIfPresent(currentActivity, forKey: .currentActivity)
        try container.encodeIfPresent(currentlyWith, forKey: .currentlyWith)
    }
}