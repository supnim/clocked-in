import Foundation
import OSLog

/// Errors that can occur during username operations
enum UsernameError: LocalizedError {
    case invalidFormat
    case tooShort
    case tooLong
    case invalidCharacters
    case reserved
    case alreadyTaken
    case claimFailed
    case userNotFound
    case notImplemented

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Username format is invalid"
        case .tooShort:
            return "Username must be at least 3 characters"
        case .tooLong:
            return "Username must be 20 characters or less"
        case .invalidCharacters:
            return "Username can only contain lowercase letters, numbers, and underscores"
        case .reserved:
            return "This username is reserved and cannot be used"
        case .alreadyTaken:
            return "This username is already taken"
        case .claimFailed:
            return "Failed to claim username. Please try again."
        case .userNotFound:
            return "User not found"
        case .notImplemented:
            return "This feature requires backend implementation"
        }
    }
}

/// Validation result with specific error information
enum UsernameValidationResult {
    case valid
    case invalid(UsernameError)

    var isValid: Bool {
        if case .valid = self { return true }
        return false
    }

    var error: UsernameError? {
        if case .invalid(let error) = self { return error }
        return nil
    }
}

@MainActor
@Observable
final class UsernameService {
    static let shared = UsernameService()

    private let log = Logger(subsystem: "clocked-in", category: "username")

    /// Reserved usernames that cannot be claimed
    private let reservedUsernames: Set<String> = [
        "admin",
        "system",
        "clockedin",
        "support",
        "help",
        "null",
        "undefined"
    ]

    /// Username validation regex: 3-20 chars, lowercase a-z, 0-9, underscore only
    private let usernameRegex = #/^[a-z0-9_]{3,20}$/#

    private init() {}

    // MARK: - Validation

    /// Validates username format (does not check availability)
    /// - Parameter username: The username to validate
    /// - Returns: true if format is valid, false otherwise
    func validateUsername(_ username: String) -> Bool {
        return validateUsernameDetailed(username).isValid
    }

    /// Validates username with detailed error information
    /// - Parameter username: The username to validate
    /// - Returns: Validation result with specific error if invalid
    func validateUsernameDetailed(_ username: String) -> UsernameValidationResult {
        // Check length bounds first for specific error messages
        guard username.count >= 3 else {
            return .invalid(.tooShort)
        }

        guard username.count <= 20 else {
            return .invalid(.tooLong)
        }

        // Check character set (lowercase letters, numbers, underscore)
        guard username.wholeMatch(of: usernameRegex) != nil else {
            return .invalid(.invalidCharacters)
        }

        // Check reserved words
        guard !reservedUsernames.contains(username) else {
            return .invalid(.reserved)
        }

        return .valid
    }

    // MARK: - Availability

    /// Checks if a username is available for claiming
    /// - Parameter username: The username to check (will be normalized to lowercase)
    /// - Returns: true if available, false if taken
    /// - Throws: UsernameError for invalid format, or backend errors
    func checkAvailability(_ username: String) async throws -> Bool {
        let normalizedUsername = username.lowercased()

        // Validate format first
        let validation = validateUsernameDetailed(normalizedUsername)
        guard validation.isValid else {
            log.warning("Username validation failed for '\(normalizedUsername)': \(validation.error?.localizedDescription ?? "unknown")")
            throw validation.error!
        }

        log.debug("Checking availability for username '\(normalizedUsername)'")

        let response: CheckUsernameResponse = try await APIClient.shared.get("/api/users/check-username/\(normalizedUsername)")
        return response.available
    }

    // MARK: - Claiming

    /// Claims a username for a user
    /// - Parameters:
    ///   - username: The username to claim (will be normalized to lowercase)
    ///   - userId: The user ID claiming the username
    /// - Throws: UsernameError if validation fails, username is taken, or write fails
    func claimUsername(_ username: String, for userId: String) async throws {
        let normalizedUsername = username.lowercased()

        // Validate format first
        let validation = validateUsernameDetailed(normalizedUsername)
        guard validation.isValid else {
            log.warning("Cannot claim username '\(normalizedUsername)': validation failed")
            throw validation.error!
        }

        log.info("Attempting to claim username '\(normalizedUsername)' for user \(userId)")

        let body = ClaimUsernameRequest(username: normalizedUsername)
        let _: ClaimUsernameResponse = try await APIClient.shared.post("/api/users/username", body: body)
    }

    /// Releases a username (for account deletion or username change)
    /// - Parameters:
    ///   - username: The username to release
    ///   - userId: The user ID that owns the username (for verification)
    /// - Throws: Error if the user doesn't own the username or write fails
    func releaseUsername(_ username: String, for userId: String) async throws {
        let normalizedUsername = username.lowercased()

        log.info("Attempting to release username '\(normalizedUsername)' for user \(userId)")

        // Use PATCH /api/users/me to clear the username
        let body: [String: String?] = ["username": nil]
        let _: ClaimUsernameResponse = try await APIClient.shared.patch("/api/users/me", body: body)
    }

    /// Changes a user's username atomically
    /// - Parameters:
    ///   - oldUsername: The current username
    ///   - newUsername: The new username to claim
    ///   - userId: The user ID
    /// - Throws: UsernameError if validation fails, new username is taken, or write fails
    func changeUsername(from oldUsername: String, to newUsername: String, for userId: String) async throws {
        let normalizedNew = newUsername.lowercased()

        // Validate new username
        let validation = validateUsernameDetailed(normalizedNew)
        guard validation.isValid else {
            throw validation.error!
        }

        log.info("Attempting to change username from '\(oldUsername.lowercased())' to '\(normalizedNew)' for user \(userId)")

        let body = ClaimUsernameRequest(username: normalizedNew)
        let _: ClaimUsernameResponse = try await APIClient.shared.post("/api/users/username", body: body)
    }

    /// Looks up a user ID by username
    /// - Parameter username: The username to look up
    /// - Returns: The user ID if found, nil otherwise
    func getUserId(for username: String) async throws -> String? {
        let normalizedUsername = username.lowercased()

        log.debug("Looking up user ID for username '\(normalizedUsername)'")

        do {
            let user: PublicUser = try await APIClient.shared.get("/api/users/\(normalizedUsername)")
            return user.id
        } catch {
            return nil
        }
    }

    /// Searches for users by username prefix
    /// - Parameter query: The search query (username prefix)
    /// - Returns: Array of matching users (up to 10)
    func searchUsers(query: String) async throws -> [PublicUser] {
        let normalizedQuery = query.lowercased()

        guard normalizedQuery.count >= 2 else {
            return []
        }

        log.debug("Searching for users with prefix '\(normalizedQuery)'")

        let encoded = normalizedQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? normalizedQuery
        return try await APIClient.shared.get("/api/users/search?q=\(encoded)")
    }
}

// MARK: - API Models

private struct CheckUsernameResponse: Decodable {
    let available: Bool
}

private struct ClaimUsernameRequest: Encodable {
    let username: String
}

private struct ClaimUsernameResponse: Decodable {}

struct PublicUser: Decodable, Identifiable, Hashable {
    let id: String
    let username: String
    let displayName: String?
    let avatarUrl: String?

    var name: String { displayName ?? username }

    enum CodingKeys: String, CodingKey {
        case id, username
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
    }
}
