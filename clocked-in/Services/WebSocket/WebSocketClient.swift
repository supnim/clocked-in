import Foundation
import AppKit
import OSLog

/// Real-time presence connection (see v1 contract: `/ws?token=...`).
///
/// Lifecycle:
/// - `connect(token:)` tears down any existing socket and opens a new one.
/// - The connection counts as established on the server's `{"type":"connected"}`
///   (or, defensively, on the first message of any type).
/// - Liveness: a `heartbeat` is sent every 15s together with a WebSocket ping. If no
///   `heartbeat_ack` arrives for 45s, or the ping fails, the socket is considered dead.
/// - Unexpected drops reconnect forever with exponential backoff (capped at 60s) + jitter.
///   System wake and network-available trigger an immediate reconnect.
/// - A handshake rejected with HTTP 401/403 (or close code 4001) triggers one silent
///   re-auth via `APIClient.attemptReauthentication()`, then `ErrorHandler.reportAuthFailure()`.
@MainActor
@Observable
final class WebSocketClient {
    static let shared = WebSocketClient()

    @ObservationIgnored
    private var webSocket: URLSessionWebSocketTask?
    @ObservationIgnored
    private var heartbeatTask: Task<Void, Never>?
    @ObservationIgnored
    private var receiveTask: Task<Void, Never>?
    @ObservationIgnored
    private var reconnectTask: Task<Void, Never>?
    @ObservationIgnored
    private var authRecoveryTask: Task<Void, Never>?

    /// Incremented for every new socket; late callbacks from older sockets are ignored.
    @ObservationIgnored
    private var connectionGeneration = 0

    // Timing
    private let heartbeatInterval: Duration = .seconds(15)
    private let ackTimeoutSeconds: TimeInterval = 45
    private let initialBackoffSeconds: Double = 1.0
    private let maxBackoffSeconds: Double = 60.0

    // Close codes used by the server
    private let closeCodeInvalidToken = 4001
    private let closeCodeAccountDeleted = 4003
    private let closeCodeReplaced = 4000

    // Reconnection state
    @ObservationIgnored
    private var storedToken: String?
    @ObservationIgnored
    private var isIntentionalDisconnect = false
    @ObservationIgnored
    private var lastAckAt: Date?
    @ObservationIgnored
    private var consecutiveAuthFailures = 0
    @ObservationIgnored
    private var wakeObserver: NSObjectProtocol?

    /// Number of reconnect attempts since the last successful connection (for UI).
    var reconnectAttempts = 0
    var isConnected = false
    var isReconnecting = false

    @ObservationIgnored
    private var isConnecting = false

    /// Most recent `initial_presence` payload, kept so a listener that attaches after
    /// the socket connected can still apply it. Observable (UI uses nil = still loading).
    private(set) var latestInitialPresence: [FriendPresenceData]?

    /// Callback when connection state changes (for UI updates)
    @ObservationIgnored
    var onConnectionStateChange: ((Bool) -> Void)?

    // Callbacks
    @ObservationIgnored
    var onPresenceUpdate: ((PresenceUpdate) -> Void)?
    @ObservationIgnored
    var onNudge: ((NudgeMessage) -> Void)?
    @ObservationIgnored
    var onFriendRequest: ((FriendRequestNotification) -> Void)?
    @ObservationIgnored
    var onInitialPresence: (([FriendPresenceData]) -> Void)?
    /// Called when the token is rejected and silent re-auth failed. If nil,
    /// `ErrorHandler.shared.reportAuthFailure()` is used.
    @ObservationIgnored
    var onAuthenticationFailed: (() -> Void)?

    private let log = Logger(subsystem: "com.clockedin", category: "WebSocketClient")

    private init() {
        observeSystemWake()
    }

    private func buildWebSocketURL(token: String) -> URL? {
        let baseURL = AppConfig.shared.wsBaseURL.appendingPathComponent("ws")
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "token", value: token)]
        return components?.url
    }

    // MARK: - Public connection API

    /// Connects with the given token, replacing any existing connection.
    func connect(token: String) {
        storedToken = token
        isIntentionalDisconnect = false
        reconnectAttempts = 0
        consecutiveAuthFailures = 0
        reconnectTask?.cancel()
        reconnectTask = nil
        authRecoveryTask?.cancel()
        authRecoveryTask = nil
        openConnection()
    }

    /// Explicitly disconnect and stop all reconnection attempts.
    func disconnect() {
        isIntentionalDisconnect = true
        reconnectTask?.cancel()
        reconnectTask = nil
        authRecoveryTask?.cancel()
        authRecoveryTask = nil
        tearDownConnection()
        isReconnecting = false
        reconnectAttempts = 0
        latestInitialPresence = nil
    }

    /// Manually trigger a reconnection attempt (e.g. retry button). No-op when connected,
    /// signed out, or intentionally disconnected.
    func reconnect() {
        guard storedToken != nil, !isIntentionalDisconnect else { return }
        guard !isConnected else { return }
        reconnectNow()
    }

    /// Network became available again: reconnect immediately if not connected.
    func handleNetworkAvailable() {
        guard storedToken != nil, !isIntentionalDisconnect else { return }
        if isConnected {
            // The old socket may be dead after a network change; verify with a ping.
            checkLiveness(generation: connectionGeneration, force: true)
        } else {
            reconnectNow()
        }
    }

    /// Clear stored token (call when user logs out)
    func clearToken() {
        storedToken = nil
    }

    // MARK: - Connection internals

    private func reconnectNow() {
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempts = 0
        isReconnecting = true
        openConnection()
    }

    private func openConnection() {
        guard !isIntentionalDisconnect else { return }
        guard let token = storedToken, let url = buildWebSocketURL(token: token) else { return }

        // Never run two sockets at once
        tearDownConnection()

        connectionGeneration &+= 1
        let generation = connectionGeneration

        let task = URLSession.shared.webSocketTask(with: url)
        webSocket = task
        isConnecting = true
        lastAckAt = nil
        task.resume()

        receiveTask = Task { [weak self] in
            await self?.receiveLoop(task: task, generation: generation)
        }
    }

    /// Cancels tasks and closes the current socket without scheduling a reconnect.
    private func tearDownConnection() {
        connectionGeneration &+= 1
        heartbeatTask?.cancel()
        heartbeatTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        isConnecting = false
        lastAckAt = nil
        let wasConnected = isConnected
        isConnected = false
        if wasConnected {
            onConnectionStateChange?(false)
        }
    }

    private func receiveLoop(task: URLSessionWebSocketTask, generation: Int) async {
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                guard generation == connectionGeneration, !Task.isCancelled else { return }
                handleMessage(message, generation: generation)
            } catch {
                guard generation == connectionGeneration, !Task.isCancelled else { return }
                handleReceiveFailure(task: task, error: error)
                return
            }
        }
    }

    private func handleReceiveFailure(task: URLSessionWebSocketTask, error: Error) {
        let httpStatus = (task.response as? HTTPURLResponse)?.statusCode
        let closeCode = task.closeCode.rawValue
        log.info("WebSocket receive failed (http: \(httpStatus ?? 0), close: \(closeCode)): \(error.localizedDescription)")

        if closeCode == closeCodeAccountDeleted {
            tearDownConnection()
            failAuthentication()
            return
        }

        if httpStatus == 401 || httpStatus == 403 || closeCode == closeCodeInvalidToken {
            tearDownConnection()
            recoverFromAuthenticationFailure()
            return
        }

        if closeCode == closeCodeReplaced {
            // Another connection for this account took over; don't fight it.
            log.info("WebSocket replaced by a newer connection; not reconnecting")
            tearDownConnection()
            isReconnecting = false
            return
        }

        handleUnexpectedDisconnect()
    }

    private func markConnected(generation: Int) {
        guard generation == connectionGeneration, !isConnected else { return }
        isConnecting = false
        isConnected = true
        isReconnecting = false
        reconnectAttempts = 0
        consecutiveAuthFailures = 0
        lastAckAt = Date()
        startHeartbeat(generation: generation)
        onConnectionStateChange?(true)

        // Re-send current presence / flush queued update (or go_offline when invisible)
        Task {
            await PresenceManager.shared.connectionDidOpen()
        }
    }

    private func handleUnexpectedDisconnect() {
        guard !isIntentionalDisconnect else { return }
        tearDownConnection()
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard !isIntentionalDisconnect, storedToken != nil else {
            isReconnecting = false
            return
        }

        reconnectTask?.cancel()
        isReconnecting = true
        reconnectAttempts += 1

        // Exponential backoff 1, 2, 4 … 60s, plus up to 20% jitter
        let exponent = Double(min(reconnectAttempts - 1, 10))
        let base = min(initialBackoffSeconds * pow(2.0, exponent), maxBackoffSeconds)
        let delay = base + Double.random(in: 0...(base * 0.2))
        log.info("Reconnecting in \(delay, format: .fixed(precision: 1))s (attempt \(self.reconnectAttempts))")

        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.openConnection()
        }
    }

    // MARK: - Authentication failure

    private func recoverFromAuthenticationFailure() {
        consecutiveAuthFailures += 1
        reconnectTask?.cancel()
        reconnectTask = nil
        isReconnecting = false

        // A fresh token was already rejected once — give up.
        guard consecutiveAuthFailures <= 1 else {
            failAuthentication()
            return
        }

        let failedToken = storedToken
        authRecoveryTask?.cancel()
        authRecoveryTask = Task { [weak self] in
            let success = await APIClient.shared.attemptReauthentication()
            guard let self, !Task.isCancelled, !self.isIntentionalDisconnect else { return }

            if self.storedToken != failedToken {
                // Someone (AuthManager) already reconnected with a new token.
                return
            }
            if success, let newToken = APIClient.shared.currentToken, newToken != failedToken {
                let failures = self.consecutiveAuthFailures
                self.connect(token: newToken)
                self.consecutiveAuthFailures = failures
            } else {
                self.failAuthentication()
            }
        }
    }

    private func failAuthentication() {
        log.warning("WebSocket authentication failed; giving up")
        storedToken = nil
        isReconnecting = false
        reconnectAttempts = 0
        if let onAuthenticationFailed {
            onAuthenticationFailed()
        } else {
            ErrorHandler.shared.reportAuthFailure()
        }
    }

    // MARK: - Heartbeat & liveness

    private func startHeartbeat(generation: Int) {
        heartbeatTask?.cancel()
        let interval = heartbeatInterval
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self, generation == self.connectionGeneration else { return }
                await self.send(["type": "heartbeat"])
                self.checkLiveness(generation: generation, force: false)
            }
        }
    }

    /// Fails the connection if heartbeats have gone unacknowledged for too long, and
    /// sends a WebSocket ping whose failure also tears the connection down.
    private func checkLiveness(generation: Int, force: Bool) {
        guard generation == connectionGeneration, let task = webSocket else { return }

        if !force, let lastAckAt, Date().timeIntervalSince(lastAckAt) > ackTimeoutSeconds {
            log.warning("No heartbeat_ack for \(Int(self.ackTimeoutSeconds))s; reconnecting")
            handleUnexpectedDisconnect()
            return
        }

        task.sendPing { [weak self] error in
            guard error != nil else { return }
            Task { @MainActor [weak self] in
                guard let self, generation == self.connectionGeneration else { return }
                self.log.warning("WebSocket ping failed; reconnecting")
                self.handleUnexpectedDisconnect()
            }
        }
    }

    // MARK: - System wake

    private func observeSystemWake() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleSystemWake()
            }
        }
    }

    private func handleSystemWake() {
        guard storedToken != nil, !isIntentionalDisconnect else { return }
        log.info("System woke; reconnecting WebSocket")
        // Sockets rarely survive sleep — always start fresh.
        reconnectNow()
    }

    // MARK: - Incoming messages

    private func handleMessage(_ message: URLSessionWebSocketTask.Message, generation: Int) {
        let data: Data
        switch message {
        case .string(let text):
            data = Data(text.utf8)
        case .data(let raw):
            data = raw
        @unknown default:
            return
        }

        guard let envelope = try? JSONDecoder().decode(WSEnvelope.self, from: data) else {
            return
        }

        // Any message proves the connection is up (servers always send "connected" first).
        markConnected(generation: generation)

        switch envelope.type {
        case "connected":
            break
        case "heartbeat_ack":
            lastAckAt = Date()
        case "initial_presence":
            if let presences = WSDecoding.decodeInitialPresence(from: data) {
                latestInitialPresence = presences
                onInitialPresence?(presences)
            }
        case "presence_update":
            if let update = WSDecoding.decodePayload(PresenceUpdate.self, from: data) {
                onPresenceUpdate?(update)
            }
        case "nudge":
            if let nudge = WSDecoding.decodePayload(NudgeMessage.self, from: data) {
                onNudge?(nudge)
            }
        case "friend_request":
            if let request = WSDecoding.decodePayload(FriendRequestNotification.self, from: data) {
                onFriendRequest?(request)
            }
        default:
            break
        }
    }

    // MARK: - Outgoing messages

    /// Sends the current user's presence. Refused while invisible or disconnected.
    func sendPresence(_ payload: PresencePayload) async {
        guard !AppSettings.shared.isInvisible else { return }
        guard isConnected else { return }
        await send(payload.message())
    }

    /// Sends presence for an activity. Hidden apps (or status "ghost") are sent as
    /// "ghost" with no app fields; window title / browser domain are never sent (v1).
    /// Refused while invisible.
    func sendPresenceUpdate(_ activity: Activity, status: String = "online") async {
        let hiddenApps = AppSettings.shared.hiddenApps
        let payload: PresencePayload
        if status == PresencePayload.Status.ghost.rawValue || hiddenApps.contains(activity.bundleId) {
            payload = .ghost
        } else {
            payload = PresencePayload.make(
                activity: activity,
                isIdle: status == PresencePayload.Status.away.rawValue,
                hiddenApps: hiddenApps
            )
        }
        await sendPresence(payload)
    }

    /// Tells the server to drop our presence immediately (friends see us offline).
    /// Used by invisible mode and before sign-out/quit.
    func sendGoOffline() async {
        await send(["type": "go_offline"])
    }

    func sendNudge(to userId: String) async {
        await send([
            "type": "nudge",
            "to_user_id": userId
        ])
    }

    private func send(_ payload: [String: Any]) async {
        guard let webSocket else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let string = String(data: data, encoding: .utf8) else {
            return
        }
        do {
            try await webSocket.send(.string(string))
        } catch {
            log.debug("WebSocket send failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Message Types

/// FriendPresence as sent by the server (contract):
/// `{"user_id", "online", "status", "app_name", "bundle_id", "app_icon",
///   "window_title": null, "browser_domain": null, "updated_at": <unix ms>}`
struct FriendPresenceData: Decodable {
    let userId: String
    let online: Bool?
    let status: String?
    let appName: String?
    let bundleId: String?
    let windowTitle: String?
    let browserDomain: String?
    /// Base64 PNG (`app_icon`; legacy `app_icon_b64` also accepted)
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
        case appIcon = "app_icon"
        case appIconB64 = "app_icon_b64"
        case lastSeen = "last_seen"
        case updatedAt = "updated_at"
        case user
    }

    init(
        userId: String,
        online: Bool?,
        status: String?,
        appName: String? = nil,
        bundleId: String? = nil,
        windowTitle: String? = nil,
        browserDomain: String? = nil,
        appIconB64: String? = nil,
        lastSeen: Int64? = nil,
        updatedAt: Int64? = nil,
        user: PresenceUserData? = nil
    ) {
        self.userId = userId
        self.online = online
        self.status = status
        self.appName = appName
        self.bundleId = bundleId
        self.windowTitle = windowTitle
        self.browserDomain = browserDomain
        self.appIconB64 = appIconB64
        self.lastSeen = lastSeen
        self.updatedAt = updatedAt
        self.user = user
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decode(String.self, forKey: .userId)
        online = Self.decodeLenientBool(container, .online)
        status = try? container.decodeIfPresent(String.self, forKey: .status)
        appName = try? container.decodeIfPresent(String.self, forKey: .appName)
        bundleId = try? container.decodeIfPresent(String.self, forKey: .bundleId)
        windowTitle = try? container.decodeIfPresent(String.self, forKey: .windowTitle)
        browserDomain = try? container.decodeIfPresent(String.self, forKey: .browserDomain)
        let icon = try? container.decodeIfPresent(String.self, forKey: .appIcon)
        let legacyIcon = try? container.decodeIfPresent(String.self, forKey: .appIconB64)
        appIconB64 = icon ?? legacyIcon
        lastSeen = Self.decodeLenientInt64(container, .lastSeen)
        updatedAt = Self.decodeLenientInt64(container, .updatedAt)
        user = try? container.decodeIfPresent(PresenceUserData.self, forKey: .user)
    }

    /// Strict Bool per contract; tolerates legacy "true"/"1" strings.
    private static func decodeLenientBool(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Bool? {
        if let value = try? container.decodeIfPresent(Bool.self, forKey: key) {
            return value
        }
        if let string = try? container.decodeIfPresent(String.self, forKey: key) {
            return ["true", "1"].contains(string.lowercased())
        }
        return nil
    }

    /// Strict Int (unix ms) per contract; tolerates legacy numeric strings.
    private static func decodeLenientInt64(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Int64? {
        if let value = try? container.decodeIfPresent(Int64.self, forKey: key) {
            return value
        }
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
            return Int64(value)
        }
        if let string = try? container.decodeIfPresent(String.self, forKey: key) {
            return Int64(string)
        }
        return nil
    }

    /// Parsed `status` field
    var presenceStatus: PresenceStatus? {
        status.flatMap { PresenceStatus(rawValue: $0) }
    }
}

/// `presence_update` carries the same FriendPresence fields as `initial_presence`.
typealias PresenceUpdate = FriendPresenceData

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

// MARK: - WebSocket Envelope Types

private struct WSEnvelope: Decodable {
    let type: String
}

private struct WSDataMessage<T: Decodable>: Decodable {
    let data: T
}

private struct WSFriendsMessage: Decodable {
    let friends: [FriendPresenceData]
}

/// Decoding helpers that accept both the flat contract shape
/// (`{"type": ..., ...fields}`) and the legacy `{"type": ..., "data": {...}}` wrapper.
enum WSDecoding {
    static func decodePayload<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        let decoder = JSONDecoder()
        if let wrapped = try? decoder.decode(WSDataMessage<T>.self, from: data) {
            return wrapped.data
        }
        return try? decoder.decode(T.self, from: data)
    }

    static func decodeInitialPresence(from data: Data) -> [FriendPresenceData]? {
        let decoder = JSONDecoder()
        if let message = try? decoder.decode(WSFriendsMessage.self, from: data) {
            return message.friends
        }
        if let wrapped = try? decoder.decode(WSDataMessage<[FriendPresenceData]>.self, from: data) {
            return wrapped.data
        }
        return nil
    }
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
