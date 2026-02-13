import Foundation
import SwiftUI
import AppKit

@MainActor
@Observable
final class ActivityMonitor {
    @ObservationIgnored
    nonisolated(unsafe) private var debounceTask: Task<Void, Never>?

    // Session manager for handling activity changes
    private weak var sessionManager: ActivitySessionManager?

    var currentActivity: Activity?

    init() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleAppChange(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        // Connect to session manager on app launch
        Task { @MainActor in
            connectToSessionManager(ActivitySessionManager.shared)
        }
    }

    // Connect to session manager for activity tracking
    private func connectToSessionManager(_ sessionManager: ActivitySessionManager) {
        self.sessionManager = sessionManager
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        debounceTask?.cancel()
    }

    @objc nonisolated private func handleAppChange(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }

        Task { @MainActor in
            // Cancel previous debounce
            debounceTask?.cancel()

            // Debounce 2 seconds
            debounceTask = Task {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }

                let browserURL = BrowserURLFetcher.getCurrentURL(for: app.bundleIdentifier ?? "")
                let (browserDomain, browserTitle) = extractBrowserInfo(from: browserURL)

                 let activity = Activity(
                     appName: app.localizedName ?? "Unknown",
                     bundleId: app.bundleIdentifier ?? "",
                     windowTitle: getWindowTitle(for: app),
                     browserURL: browserURL,
                     browserDomain: browserDomain,
                     browserTitle: browserTitle,
                     appIcon: getAppIconData(for: app),
                     timestamp: Date()
                 )

                 currentActivity = activity

                 // Notify session manager of activity change (creates sessions)
                 await sessionManager?.handleActivityChange(activity)

                 // Notify presence manager of activity change (updates Realtime DB)
                 await PresenceManager.shared.updatePresence(for: activity)
            }
        }
    }

    private func getWindowTitle(for app: NSRunningApplication) -> String? {
        // Get all windows
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        // Find window belonging to this app
        for window in windowList {
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? Int,
                  ownerPID == app.processIdentifier,
                  let windowName = window[kCGWindowName as String] as? String,
                  !windowName.isEmpty else { continue }
            return windowName
        }
        return nil
    }

    private func getAppIconData(for app: NSRunningApplication) -> Data? {
        guard let icon = app.icon else { return nil }
        return icon.tiffRepresentation
    }

    private func extractBrowserInfo(from urlString: String?) -> (domain: String?, title: String?) {
        guard let urlString = urlString, let url = URL(string: urlString) else {
            return (nil, nil)
        }

        let domain = url.host
        // For browser title, we might use window title or a generic title
        // For now, return nil as browser title (tab title) is harder to get
        return (domain, nil)
    }
}