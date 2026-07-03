import Foundation

struct FriendRequest: Codable, Identifiable, Hashable {
    let id: String
    let senderId: String
    let senderUsername: String
    let senderDisplayName: String?
    let senderAvatarUrl: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case senderId = "sender_id"
        case senderUsername = "sender_username"
        case senderDisplayName = "sender_display_name"
        case senderAvatarUrl = "sender_avatar_url"
        case createdAt = "created_at"
    }

    // Convenience accessors for backward compatibility
    var fromUid: String { senderId }
    var fromName: String { senderDisplayName ?? senderUsername }
    var fromAvatar: String? { senderAvatarUrl }
}