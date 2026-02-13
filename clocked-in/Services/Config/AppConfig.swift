import Foundation

/// Centralized configuration for app-wide settings
/// TODO: Make configurable via Info.plist or environment variables for different build configurations
final class AppConfig {
    static let shared = AppConfig()

    let apiBaseURL: URL
    let wsBaseURL: URL

    private init() {
        // Default to localhost for development
        self.apiBaseURL = URL(string: "http://localhost:8000")!
        self.wsBaseURL = URL(string: "ws://localhost:8000")!
    }
}
