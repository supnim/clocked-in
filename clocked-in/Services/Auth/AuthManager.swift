import Foundation
import AppKit
import Security
import Observation
import AuthenticationServices
import OSLog

@MainActor
@Observable
final class AuthManager {
    static let shared = AuthManager()

    var currentUser: User?
    var isAuthenticated: Bool { currentUser != nil && authToken != nil }
    var isLoading = false

    private var authToken: String?

    /// Whether the user needs to pick a username (new device registration)
    var needsUsername = false

    private let log = Logger(subsystem: "com.clockedin", category: "AuthManager")

    private let keychainService = "com.clockedin.auth"
    private let tokenKey = "authToken"
    private let userIdKey = "userId"

    private init() {
        // Try restore on init
        Task {
            await restoreSession()
        }
    }

    // MARK: - Device-ID Auth (primary, frictionless)

    /// Registers or logs in with a device-generated UUID. No user interaction needed.
    func signInWithDevice() async throws {
        isLoading = true
        defer { isLoading = false }

        let deviceId = IdentityService.shared.getOrCreateUserUUID()

        let body = DeviceRegisterRequest(deviceId: deviceId)
        let response: DeviceRegisterResponse = try await APIClient.shared.post("/auth/device", body: body)

        // Store credentials
        saveToKeychain(key: tokenKey, value: response.token)
        saveToKeychain(key: userIdKey, value: response.userId)

        authToken = response.token
        APIClient.shared.setToken(response.token)

        // Fetch user profile
        await fetchCurrentUser()

        // If signOut was triggered during fetch (e.g. 401), bail out
        guard isAuthenticated else { return }

        // Connect WebSocket
        WebSocketClient.shared.connect(token: response.token)

        // If new user, they need to pick a username
        if response.isNew {
            needsUsername = true
        }
    }

    func signInWithGoogle() {
        // Open browser to OAuth endpoint
        let url = AppConfig.shared.apiBaseURL.appendingPathComponent("auth/google")
        NSWorkspace.shared.open(url)
    }

    /// Initiates Apple Sign-In flow and authenticates with the backend.
    /// - Throws: AppleSignInError or network errors
    func signInWithApple() async throws {
        isLoading = true
        defer { isLoading = false }

        // Get Apple credential via native Sign in with Apple
        let credential = try await AppleSignInService.shared.signIn()

        // Extract identity token
        guard let identityTokenData = credential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8) else {
            throw AppleSignInError.missingIdentityToken
        }

        // Build full name from components (only provided on first sign-in)
        var fullName: String?
        if let nameComponents = credential.fullName {
            let formatter = PersonNameComponentsFormatter()
            let name = formatter.string(from: nameComponents)
            if !name.isEmpty {
                fullName = name
            }
        }

        // Send to backend for verification and JWT
        let request = AppleAuthRequest(
            identityToken: identityToken,
            fullName: fullName,
            email: credential.email
        )

        let response: AppleAuthResponse = try await APIClient.shared.post("/auth/apple", body: request)

        // Store credentials
        saveToKeychain(key: tokenKey, value: response.token)
        saveToKeychain(key: userIdKey, value: response.userId)

        authToken = response.token
        APIClient.shared.setToken(response.token)

        // Fetch user profile
        await fetchCurrentUser()

        // Connect WebSocket
        WebSocketClient.shared.connect(token: response.token)
    }

    func handleAuthCallback(url: URL) async {
        // Parse clockedin://auth?token=xxx&user_id=yyy
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let token = components.queryItems?.first(where: { $0.name == "token" })?.value,
              let userId = components.queryItems?.first(where: { $0.name == "user_id" })?.value else {
            return
        }

        // Store token
        saveToKeychain(key: tokenKey, value: token)
        saveToKeychain(key: userIdKey, value: userId)

        authToken = token
        APIClient.shared.setToken(token)

        // Fetch user profile
        await fetchCurrentUser()

        // Connect WebSocket
        WebSocketClient.shared.connect(token: token)
    }

    func signOut() {
        // Stop all services before disconnecting
        PresenceListener.shared.stopListening()
        PresenceManager.shared.stopPresence()
        PresenceManager.shared.clearPendingUpdates()
        IdleDetector.shared.stop()
        EventMonitors.shared.stop()
        CachedFriendsService.shared.clearCache()

        // Disconnect WebSocket
        WebSocketClient.shared.disconnect()

        // Clear keychain
        deleteFromKeychain(key: tokenKey)
        deleteFromKeychain(key: userIdKey)

        authToken = nil
        currentUser = nil
        needsUsername = false
        APIClient.shared.setToken(nil)
    }

    private func restoreSession() async {
        guard let token = readFromKeychain(key: tokenKey),
              let _ = readFromKeychain(key: userIdKey) else {
            return
        }

        authToken = token
        APIClient.shared.setToken(token)

        // Try to fetch user - if fails, token is expired
        await fetchCurrentUser()

        if currentUser != nil {
            WebSocketClient.shared.connect(token: token)
        } else {
            // Token expired, clear
            signOut()
        }
    }

    private func fetchCurrentUser() async {
        isLoading = true
        defer { isLoading = false }

        do {
            currentUser = try await APIClient.shared.get("/api/users/me")
        } catch let error {
            // Log the error through ErrorHandler
            ErrorHandler.shared.handle(error, context: "fetchCurrentUser", showToUser: false)

            // Check if this is an auth error (401)
            let appError = AppError.from(error)
            if appError.requiresReauth {
                // Token is invalid, trigger sign out
                signOut()
            }

            currentUser = nil
        }
    }

    // MARK: - Keychain Helpers

    private func saveToKeychain(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        // Delete existing
        SecItemDelete(query as CFDictionary)

        // Add new
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            log.error("Keychain save failed with status: \(status)")
        }
    }

    private func readFromKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }

    private func deleteFromKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Apple Auth Models

/// Request body for Apple Sign-In backend endpoint
struct AppleAuthRequest: Encodable {
    let identityToken: String
    let fullName: String?
    let email: String?

    enum CodingKeys: String, CodingKey {
        case identityToken = "identity_token"
        case fullName = "full_name"
        case email
    }
}

/// Response from Apple Sign-In backend endpoint
struct AppleAuthResponse: Decodable {
    let token: String
    let userId: String

    enum CodingKeys: String, CodingKey {
        case token
        case userId = "user_id"
    }
}

// MARK: - Device Auth Models

struct DeviceRegisterRequest: Encodable {
    let deviceId: String
    let platform: String = "macos"

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case platform
    }
}

struct DeviceRegisterResponse: Decodable {
    let token: String
    let userId: String
    let isNew: Bool

    enum CodingKeys: String, CodingKey {
        case token
        case userId = "user_id"
        case isNew = "is_new"
    }
}
