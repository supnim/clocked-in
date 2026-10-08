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

    /// The current bearer token (read-only; used by AppDelegate to connect the WebSocket).
    var currentAuthToken: String? { authToken }

    /// Whether the user needs to pick a username (new device registration)
    var needsUsername = false

    /// True once the signed-in user has a non-empty username.
    var hasUsername: Bool {
        guard let name = currentUser?.username else { return false }
        return !name.isEmpty
    }

    /// Called before local credentials are wiped so the owner (AppDelegate) can
    /// stop services and tell the server we're going offline while the socket is still up.
    @ObservationIgnored
    var onWillEndSession: (@MainActor () async -> Void)?

    /// Called after sign-out / account deletion has finished wiping local state.
    @ObservationIgnored
    var onDidEndSession: (@MainActor () -> Void)?

    @ObservationIgnored
    private var isEndingSession = false

    /// Set by user-initiated sign-out / account deletion so onboarding waits for the user
    /// instead of immediately signing back in with the device identity.
    @ObservationIgnored
    private(set) var requiresExplicitSignIn = false

    @ObservationIgnored
    private var reauthTask: Task<Bool, Never>?

    private let log = Logger(subsystem: "com.clockedin", category: "AuthManager")

    private let keychainService = "com.clockedin.auth"
    private let tokenKey = "authToken"
    private let userIdKey = "userId"

    private init() {
        // Let the API client silently re-run device auth on 401 before giving up.
        APIClient.shared.reauthenticate = {
            await AuthManager.shared.reauthenticateSilently()
        }
    }

    // MARK: - Device-ID Auth (primary, frictionless)

    /// Registers or logs in with a device-generated UUID. No user interaction needed.
    /// Does NOT connect the WebSocket; AppDelegate.startServices owns that.
    func signInWithDevice() async throws {
        requiresExplicitSignIn = false
        isLoading = true
        defer { isLoading = false }

        let response = try await performDeviceAuth()

        // Fetch user profile
        await fetchCurrentUser()

        // Profile fetch failed (network error, or 401 which already ended the session)
        guard isAuthenticated else {
            throw AppError.network(message: "Couldn't load your profile. Please try again.")
        }

        // New users, and returning users who never finished picking a name, need a username
        needsUsername = response.isNew || !hasUsername
    }

    /// Posts the device UUID to the backend and stores the returned credentials.
    @discardableResult
    private func performDeviceAuth() async throws -> DeviceRegisterResponse {
        let deviceId = IdentityService.shared.getOrCreateUserUUID()

        let body = DeviceRegisterRequest(deviceId: deviceId)
        let response: DeviceRegisterResponse = try await APIClient.shared.post("/auth/device", body: body)

        // Store credentials
        saveToKeychain(key: tokenKey, value: response.token)
        saveToKeychain(key: userIdKey, value: response.userId)

        authToken = response.token
        APIClient.shared.setToken(response.token)
        return response
    }

    /// Silently re-runs device auth (e.g. after the JWT expired). Returns true on success.
    /// Concurrent callers share one in-flight attempt.
    func reauthenticateSilently() async -> Bool {
        if let reauthTask {
            return await reauthTask.value
        }
        // Nothing to refresh if we were never signed in or are signing out.
        guard authToken != nil, !isEndingSession else { return false }

        let task = Task { @MainActor () -> Bool in
            do {
                try await self.performDeviceAuth()
                if let token = self.authToken, WebSocketClient.shared.isConnected || WebSocketClient.shared.isReconnecting {
                    // Re-open the socket with the fresh token
                    WebSocketClient.shared.disconnect()
                    WebSocketClient.shared.connect(token: token)
                }
                return true
            } catch {
                self.log.error("Silent re-authentication failed: \(error.localizedDescription)")
                return false
            }
        }
        reauthTask = task
        let result = await task.value
        reauthTask = nil
        return result
    }

    /// Re-fetches the current user's profile from the server (e.g. after claiming a username).
    func refreshCurrentUser() async {
        await fetchCurrentUser()
        if hasUsername {
            needsUsername = false
        }
    }

    // NOTE: Google sign-in and Apple account linking are hidden for v1 (see SHIP_CHECKLIST.md).
    // The code paths are kept but nothing in the UI calls them.

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
    }

    // MARK: - Sign Out / Delete Account

    /// User-initiated sign out. Stops services, wipes the auth token and caches, then the
    /// AppDelegate shows onboarding again. The device identity is kept: it is the only
    /// credential for the account, so forgetting it would strand the account forever.
    func signOut() {
        requiresExplicitSignIn = true
        Task { await endSession(forgetDevice: false) }
    }

    /// Called when the server rejects our credentials and silent re-auth failed.
    /// Keeps the device identity so onboarding can sign straight back in to the same account.
    func handleAuthFailure() {
        Task { await endSession(forgetDevice: false) }
    }

    /// Permanently deletes the account on the server, then performs the same teardown as sign-out.
    func deleteAccount() async throws {
        try await APIClient.shared.deleteAccount()
        requiresExplicitSignIn = true
        await endSession(forgetDevice: true)
    }

    private func endSession(forgetDevice: Bool) async {
        guard !isEndingSession else { return }
        // Several 401 paths can fire for the same failure; only tear down once.
        guard authToken != nil || currentUser != nil else { return }
        isEndingSession = true
        defer { isEndingSession = false }

        // 1. Stop services while the socket is still up (owner sends go_offline)
        if let onWillEndSession {
            await onWillEndSession()
        }

        // 2. Disconnect WebSocket (idempotent if the owner already did)
        WebSocketClient.shared.disconnect()

        // 3. Wipe Keychain (both services)
        deleteFromKeychain(key: tokenKey)
        deleteFromKeychain(key: userIdKey)
        if forgetDevice {
            IdentityService.shared.resetIdentity()
        }

        // 4. Clear caches and in-memory state
        PresenceManager.shared.clearPendingUpdates()
        PresenceListener.shared.clearCache()
        CachedFriendsService.shared.clearCache()
        if forgetDevice {
            AppSettings.shared.hasCompletedOnboarding = false
        }

        authToken = nil
        currentUser = nil
        needsUsername = false
        APIClient.shared.setToken(nil)

        // 5. Let the owner show onboarding again
        onDidEndSession?()
    }

    // MARK: - Session Restore

    /// Restores a saved session from the Keychain. Awaited by AppDelegate at launch
    /// before deciding between onboarding and starting services.
    func restoreSession() async {
        guard let token = readFromKeychain(key: tokenKey),
              readFromKeychain(key: userIdKey) != nil else {
            return
        }

        authToken = token
        APIClient.shared.setToken(token)

        // Try to fetch user. On 401 fetchCurrentUser ends the session.
        await fetchCurrentUser()

        if currentUser == nil, authToken != nil {
            // Network/server failure (not an auth failure): fall back to the cached
            // profile so the app can start offline and reconnect later.
            if let cached = CachedFriendsService.shared.loadCachedUserProfile() {
                currentUser = cached.user
            }
        }

        needsUsername = isAuthenticated && !hasUsername
    }

    private func fetchCurrentUser() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let user: User = try await APIClient.shared.get("/api/users/me")
            currentUser = user
            CachedFriendsService.shared.cacheUserProfile(user, pendingRequestsCount: 0)
        } catch let error {
            // Log the error through ErrorHandler
            ErrorHandler.shared.handle(error, context: "fetchCurrentUser", showToUser: false)

            // Check if this is an auth error (401)
            let appError = AppError.from(error)
            if appError.requiresReauth {
                // Token is invalid and could not be refreshed
                currentUser = nil
                await endSession(forgetDevice: false)
            }
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
