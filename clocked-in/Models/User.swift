import Foundation

struct UserSettings: Codable, Hashable {
    var nudgeShake: Bool = true
    var nudgeSound: Bool = true
    var nudgeNotification: Bool = true
    var invisible: Bool = false
    var hiddenApps: [String] = []
    var shareWindowTitle: Bool = true
    var shareBrowserDomain: Bool = true

    enum CodingKeys: String, CodingKey {
        case nudgeShake = "nudge_shake"
        case nudgeSound = "nudge_sound"
        case nudgeNotification = "nudge_notification"
        case invisible
        case hiddenApps = "hidden_apps"
        case shareWindowTitle = "share_window_title"
        case shareBrowserDomain = "share_browser_domain"
    }
}

struct User: Codable, Identifiable, Hashable {
    var id: String?
    var username: String            // 3-20 chars, lowercase, unique
    var email: String?
    var displayName: String?
    var avatarUrl: String?
    var statusMessage: String?
    var settings: UserSettings?
    var createdAt: Date
    var updatedAt: Date

    // Fallback to username if displayName is nil
    var name: String { displayName ?? username }

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case email
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case statusMessage = "status_message"
        case settings
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(
        id: String? = nil,
        username: String,
        email: String? = nil,
        displayName: String? = nil,
        avatarUrl: String? = nil,
        statusMessage: String? = nil,
        settings: UserSettings? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.username = username
        self.email = email
        self.displayName = displayName
        self.avatarUrl = avatarUrl
        self.statusMessage = statusMessage
        self.settings = settings
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
