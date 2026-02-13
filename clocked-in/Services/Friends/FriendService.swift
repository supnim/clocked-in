import Foundation

// MARK: - Response Types

struct FriendWithPresence: Codable, Identifiable {
    let userId: String
    let username: String
    let displayName: String?
    let avatarUrl: String?
    let friendsSince: Date
    let presence: PresenceData

    // Map userId to id for Identifiable conformance
    var id: String { userId }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case username
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case friendsSince = "friends_since"
        case presence
    }
}

struct PresenceData: Codable {
    let online: Bool
    let appName: String?
    let appBundleId: String?
    let windowTitle: String?
    let url: String?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case online
        case appName = "app_name"
        case appBundleId = "app_bundle_id"
        case windowTitle = "window_title"
        case url
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.online = try container.decodeIfPresent(Bool.self, forKey: .online) ?? false
        self.appName = try container.decodeIfPresent(String.self, forKey: .appName)
        self.appBundleId = try container.decodeIfPresent(String.self, forKey: .appBundleId)
        self.windowTitle = try container.decodeIfPresent(String.self, forKey: .windowTitle)
        self.url = try container.decodeIfPresent(String.self, forKey: .url)
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}

// MARK: - Empty Response

private struct EmptyResponse: Codable {}

// MARK: - FriendService

@Observable
final class FriendService {
    static let shared = FriendService()

    private let api = APIClient.shared

    private init() {}

    // MARK: - Friends

    /// Fetches the current user's friends with their presence data
    func getFriends() async throws -> [FriendWithPresence] {
        try await api.get("/api/friends")
    }

    /// Removes a friend by their user ID
    func removeFriend(_ userId: String) async throws {
        let _: EmptyResponse = try await api.delete("/api/friends/\(userId)")
    }

    // MARK: - Friend Requests

    /// Sends a friend request to a user by their username
    func sendFriendRequest(to username: String) async throws {
        let _: EmptyResponse = try await api.post("/api/friends/request/\(username)")
    }

    /// Fetches pending friend requests for the current user
    func getPendingRequests() async throws -> [FriendRequest] {
        try await api.get("/api/friends/requests")
    }

    /// Accepts a friend request by its ID
    func acceptRequest(_ requestId: String) async throws {
        let _: EmptyResponse = try await api.post("/api/friends/accept/\(requestId)")
    }

    /// Declines a friend request by its ID
    func declineRequest(_ requestId: String) async throws {
        let _: EmptyResponse = try await api.post("/api/friends/decline/\(requestId)")
    }
}
