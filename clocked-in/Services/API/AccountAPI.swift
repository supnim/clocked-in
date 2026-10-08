import Foundation

// MARK: - Models

/// A user the current user has blocked (`GET /api/users/me/blocks`).
struct BlockedUser: Decodable, Identifiable, Hashable {
    let id: String
    let username: String?
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case displayName = "display_name"
    }

    /// Best available name for display
    var name: String {
        if let displayName, !displayName.isEmpty { return displayName }
        if let username, !username.isEmpty { return "@\(username)" }
        return "Unknown user"
    }
}

private struct ReportUserRequest: Encodable {
    let reason: String
}

// MARK: - Account / Safety Endpoints

extension APIClient {
    /// Permanently deletes the current user's account (`DELETE /api/users/me` → 204).
    /// The caller is responsible for wiping local credentials afterwards.
    func deleteAccount() async throws {
        try await requestNoContent("/api/users/me", method: "DELETE")
    }

    /// Blocks a user (`POST /api/users/{id}/block` → 204). Also removes any friendship
    /// and pending requests in both directions (server side).
    func blockUser(id: String) async throws {
        try await requestNoContent("/api/users/\(id)/block", method: "POST")
    }

    /// Unblocks a user (`DELETE /api/users/{id}/block` → 204).
    func unblockUser(id: String) async throws {
        try await requestNoContent("/api/users/\(id)/block", method: "DELETE")
    }

    /// Lists users blocked by the current user (`GET /api/users/me/blocks`).
    func listBlockedUsers() async throws -> [BlockedUser] {
        try await get("/api/users/me/blocks")
    }

    /// Reports a user (`POST /api/users/{id}/report` → 204). `reason` is trimmed and
    /// truncated to the server limit of 500 characters.
    func reportUser(id: String, reason: String) async throws {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = ReportUserRequest(reason: String(trimmed.prefix(500)))
        try await requestNoContent("/api/users/\(id)/report", method: "POST", body: body)
    }
}
