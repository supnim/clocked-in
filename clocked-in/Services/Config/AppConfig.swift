import Foundation

/// Centralized configuration for app-wide settings
final class AppConfig {
    static let shared = AppConfig()

    let apiBaseURL: URL
    let wsBaseURL: URL

    private init() {
        #if DEBUG
        self.apiBaseURL = URL(string: "http://localhost:8000")!
        self.wsBaseURL = URL(string: "ws://localhost:8000")!
        #else
        self.apiBaseURL = URL(string: "https://api.clockedin.studio.gold")!
        self.wsBaseURL = URL(string: "wss://api.clockedin.studio.gold")!
        #endif
    }
}
