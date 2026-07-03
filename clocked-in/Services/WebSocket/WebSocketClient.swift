import Foundation

@MainActor
@Observable
final class WebSocketClient {
    static let shared = WebSocketClient()

    private var webSocket: URLSessionWebSocketTask?
    private var heartbeatTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?

    // Reconnection configuration (exposed for UI)
    let maxReconnectAttempts = 10
    private let initialBackoffSeconds: Double = 1.0
    private let maxBackoffSeconds: Double = 30.0

    // Reconnection state
    @ObservationIgnored
    private var storedToken: String?
    var reconnectAttempts = 0
    private var isIntentionalDisconnect = false
    private var isConnecting = false

    var isConnected = false
    var isReconnecting = false

    /// Callback when connection state changes (for UI updates)
    var onConnectionStateChange: ((Bool) -> Void)?

    // Callbacks
    var onPresenceUpdate: ((PresenceUpdate) -> Void)?
    var onNudge: ((NudgeMessage) -> Void)?
    var onFriendRequest: ((FriendRequestNotification) -> Void)?
    var onInitialPresence: (([FriendPresenceData]) -> Void)?
    var onAuthenticationFailed: (() -> Void)?

    private init() {}

    private func buildWebSocketURL(token: String) -> URL? {
        let baseURL = AppConfig.shared.wsBaseURL.appendingPathComponent("ws")
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "token", value: token)]
        return components?.url
    }

    func connect(token: String) {
        // Store token for reconnection
        storedToken = token
        isIntentionalDisconnect = false
        reconnectAttempts = 0

        performConnect(token: token)
    }

    private func performConnect(token: String) {
        guard !isConnecting else { return }
        guard let url = buildWebSocketURL(token: token) else { return }

        isConnecting = true
        webSocket = URLSession.shared.webSocketTask(with: url)
        webSocket?.resume()
        // Note: isConnected will be set true after first successful receive
        // to avoid race condition where connection fails immediately
        isReconnecting = false

        startHeartbeat()
        startReceiving()
    }

    /// Explicitly disconnect and stop all reconnection attempts
    func disconnect() {
        isIntentionalDisconnect = true
        reconnectTask?.cancel()
        reconnectTask = nil
        cleanupConnection()
    }

    private func cleanupConnection() {
        heartbeatTask?.cancel()
        receiveTask?.cancel()
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        isConnecting = false
        let wasConnected = isConnected
        isConnected = false
        isReconnecting = false
        if wasConnected {
            onConnectionStateChange?(false)
        }
    }

    /// Manually trigger a reconnection attempt
    func reconnect() {
        guard storedToken != nil else { return }
        guard !isConnected else { return }

        isIntentionalDisconnect = false
        reconnectAttempts = 0
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard !isIntentionalDisconnect else { return }
        guard let token = storedToken else { return }
        guard reconnectAttempts < maxReconnectAttempts else {
            isReconnecting = false
            return
        }

        isReconnecting = true
        reconnectAttempts += 1

        // Exponential backoff: 1s, 2s, 4s, 8s, 16s, 30s, 30s...
        let backoff = min(
            initialBackoffSeconds * pow(2.0, Double(reconnectAttempts - 1)),
            maxBackoffSeconds
        )

        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(backoff))
            guard !Task.isCancelled else { return }
            await self?.attemptReconnect(token: token)
        }
    }

    private func attemptReconnect(token: String) async {
        guard !isIntentionalDisconnect else { return }
        guard let url = buildWebSocketURL(token: token) else { return }

        let session = URLSession.shared
        let task = session.webSocketTask(with: url)
        task.resume()

        // Wait briefly to check if connection succeeds
        do {
            // Try to receive a message or ping to verify connection
            try await withTimeout(seconds: 5) {
                _ = try await task.receive()
            }

            // Connection succeeded
            self.webSocket = task
            self.isConnected = true
            self.isReconnecting = false
            self.reconnectAttempts = 0
            self.startHeartbeat()
            self.startReceiving()
        } catch let error as URLError where error.code == .userAuthenticationRequired {
            // Token is invalid - clear and stop reconnecting
            handleAuthenticationFailure()
        } catch {
            // Connection failed, try again
            task.cancel(with: .goingAway, reason: nil)
            scheduleReconnect()
        }
    }

    private func handleAuthenticationFailure() {
        storedToken = nil
        isReconnecting = false
        reconnectAttempts = 0
        onAuthenticationFailed?()
    }

    private func withTimeout<T: Sendable>(seconds: Double, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw URLError(.timedOut)
            }
            guard let result = try await group.next() else {
                throw URLError(.timedOut)
            }
            group.cancelAll()
            return result
        }
    }

    private func handleUnexpectedDisconnect() {
        guard !isIntentionalDisconnect else { return }
        cleanupConnection()
        scheduleReconnect()
    }

    /// Clear stored token (call when user logs out)
    func clearToken() {
        storedToken = nil
    }

    private func startHeartbeat() {
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { break }
                await self?.send(["type": "heartbeat"])
            }
        }
    }

    private func startReceiving() {
        receiveTask = Task { [weak self] in
            var hasReceivedFirstMessage = false
            while !Task.isCancelled {
                guard let ws = self?.webSocket else { break }
                do {
                    let message = try await self?.withTimeout(seconds: 60) {
                        try await ws.receive()
                    }
                    guard let message else { break }
                    // Mark as connected after first successful receive
                    if !hasReceivedFirstMessage {
                        hasReceivedFirstMessage = true
                        self?.isConnecting = false
                        self?.isConnected = true
                        self?.reconnectAttempts = 0
                        self?.onConnectionStateChange?(true)
                    }
                    await self?.handleMessage(message)
                } catch {
                    // Connection dropped or timed out
                    self?.handleUnexpectedDisconnect()
                    break
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        guard case .string(let text) = message,
              let data = text.data(using: .utf8) else {
            return
        }

        // Decode the envelope to get type and route to specific decoder
        guard let envelope = try? JSONDecoder().decode(WSEnvelope.self, from: data) else {
            return
        }

        switch envelope.type {
        case "presence_update":
            if let update = try? JSONDecoder().decode(WSMessage<PresenceUpdate>.self, from: data) {
                onPresenceUpdate?(update.data)
            }
        case "nudge":
            if let nudge = try? JSONDecoder().decode(WSMessage<NudgeMessage>.self, from: data) {
                onNudge?(nudge.data)
            }
        case "friend_request":
            if let request = try? JSONDecoder().decode(WSMessage<FriendRequestNotification>.self, from: data) {
                onFriendRequest?(request.data)
            }
        case "initial_presence":
            if let presences = try? JSONDecoder().decode(WSMessage<[FriendPresenceData]>.self, from: data) {
                onInitialPresence?(presences.data)
            }
        default:
            break
        }
    }

    func sendPresenceUpdate(_ activity: Activity, status: String = "online") async {
        var payload: [String: Any] = [
            "type": "presence_update",
            "data": [
                "app_name": activity.appName,
                "bundle_id": activity.bundleId,
                "status": status
            ]
        ]

        if var data = payload["data"] as? [String: Any] {
            if let windowTitle = activity.windowTitle {
                data["window_title"] = windowTitle
            }
            if let browserDomain = activity.browserDomain {
                data["browser_domain"] = browserDomain
            }
            if let iconData = activity.appIcon {
                data["app_icon_b64"] = iconData.base64EncodedString()
            }
            payload["data"] = data
        }

        await send(payload)
    }

    func sendNudge(to userId: String) async {
        await send([
            "type": "nudge",
            "data": ["to_user_id": userId]
        ])
    }

    private func send(_ payload: [String: Any]) async {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let string = String(data: data, encoding: .utf8) else {
            return
        }
        try? await webSocket?.send(.string(string))
    }
}

// MARK: - Message Types

struct PresenceUpdate: Codable {
    let userId: String
    let online: Bool?
    let status: String?
    let appName: String?
    let bundleId: String?
    let windowTitle: String?
    let browserDomain: String?
    let appIconB64: String?
    let updatedAt: Int64?
    let user: PresenceUserData?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case online, status
        case appName = "app_name"
        case bundleId = "bundle_id"
        case windowTitle = "window_title"
        case browserDomain = "browser_domain"
        case appIconB64 = "app_icon_b64"
        case updatedAt = "updated_at"
        case user
    }
}

struct NudgeMessage: Codable {
    let fromUserId: String
    let fromUsername: String?

    enum CodingKeys: String, CodingKey {
        case fromUserId = "from_user_id"
        case fromUsername = "from_username"
    }
}

struct FriendRequestNotification: Codable {
    let requestId: String
    let fromUserId: String
    let fromUsername: String

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case fromUserId = "from_user_id"
        case fromUsername = "from_username"
    }
}

struct FriendPresenceData: Codable {
    let userId: String
    let online: Bool?
    let status: String?
    let appName: String?
    let bundleId: String?
    let windowTitle: String?
    let browserDomain: String?
    let appIconB64: String?
    let lastSeen: Int64?
    let updatedAt: Int64?
    let user: PresenceUserData?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case online, status
        case appName = "app_name"
        case bundleId = "bundle_id"
        case windowTitle = "window_title"
        case browserDomain = "browser_domain"
        case appIconB64 = "app_icon_b64"
        case lastSeen = "last_seen"
        case updatedAt = "updated_at"
        case user
    }
}

// MARK: - WebSocket Envelope Types

private struct WSEnvelope: Decodable {
    let type: String
}

private struct WSMessage<T: Decodable>: Decodable {
    let type: String
    let data: T
}

// User data embedded in presence updates
struct PresenceUserData: Codable {
    let username: String
    let displayName: String?
    let avatarUrl: String?
    let statusMessage: String?

    enum CodingKeys: String, CodingKey {
        case username
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case statusMessage = "status_message"
    }
}
