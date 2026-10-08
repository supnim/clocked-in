import Foundation
import Network

/// Connection state for UI display
enum ConnectionState: Equatable {
    case online
    case offline
    case reconnecting(attempt: Int, maxAttempts: Int)

    var isOffline: Bool {
        switch self {
        case .online: return false
        case .offline, .reconnecting: return true
        }
    }

    var displayText: String {
        switch self {
        case .online:
            return "Online"
        case .offline:
            return "Offline"
        case .reconnecting(let attempt, let maxAttempts):
            // maxAttempts == 0 means unbounded (WebSocketClient retries forever)
            if maxAttempts > 0 {
                return "Reconnecting (\(attempt)/\(maxAttempts))..."
            }
            return attempt > 1 ? "Reconnecting (attempt \(attempt))..." : "Reconnecting..."
        }
    }
}

@MainActor
@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    /// Raw network availability
    var isOffline: Bool = false

    /// Combined connection state (network + WebSocket)
    var connectionState: ConnectionState {
        if isOffline {
            return .offline
        }
        let ws = WebSocketClient.shared
        if ws.isReconnecting {
            return .reconnecting(attempt: ws.reconnectAttempts, maxAttempts: 0)
        }
        return ws.isConnected ? .online : .offline
    }

    private var monitor: NWPathMonitor?
    private var queue: DispatchQueue?

    private init() {
        startMonitoring()
    }

    nonisolated deinit {
        // Deinit is nonisolated, so we need to handle cleanup differently
        // The monitor will be cleaned up when the object is deallocated
    }

    private func startMonitoring() {
        monitor = NWPathMonitor()
        queue = DispatchQueue(label: "NetworkMonitor")

        monitor?.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in
                guard let self = self else { return }
                let wasOffline = self.isOffline
                self.isOffline = !satisfied

                // If coming back online, trigger reconnection
                if wasOffline && !self.isOffline {
                    await self.handleReconnection()
                }
            }
        }

        monitor?.start(queue: queue!)
    }

    private func stopMonitoring() {
        monitor?.cancel()
        monitor = nil
        queue = nil
    }

    private func handleReconnection() async {
        // Reconnect WebSocket immediately (skips any pending backoff). Presence is
        // re-sent / the queue flushed by PresenceManager.connectionDidOpen() once the
        // server confirms the connection.
        WebSocketClient.shared.handleNetworkAvailable()

        // Mark as online in cache service
        CachedFriendsService.shared.markOnline()
    }

    /// Manually trigger a reconnection attempt
    func retryConnection() {
        guard isOffline || !WebSocketClient.shared.isConnected else { return }
        WebSocketClient.shared.reconnect()
    }
}