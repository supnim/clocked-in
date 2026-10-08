import Foundation
import SwiftUI

@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    var hiddenApps: [String] {
        didSet {
            defaults.set(hiddenApps, forKey: Keys.hiddenApps)
            guard oldValue != hiddenApps else { return }
            // Hiding the app the user is in right now must take effect immediately
            Task {
                await PresenceManager.shared.hiddenAppsDidChange()
            }
        }
    }

    // MARK: - Hidden Apps Management

    func hideApp(_ bundleId: String) {
        guard !bundleId.isEmpty, !hiddenApps.contains(bundleId) else { return }
        hiddenApps.append(bundleId)
    }

    func unhideApp(_ bundleId: String) {
        hiddenApps.removeAll { $0 == bundleId }
    }

    func isAppHidden(_ bundleId: String) -> Bool {
        hiddenApps.contains(bundleId)
    }

    /// Invisible mode: stops all presence sharing immediately (sends go_offline and drops
    /// queued updates). Friends' presence is still shown to the user.
    var isInvisible: Bool {
        didSet {
            defaults.set(isInvisible, forKey: Keys.isInvisible)
            guard oldValue != isInvisible else { return }
            // Clear stale join notification tracking when becoming visible
            if !isInvisible {
                NotchNotificationManager.shared.clearJoinNotificationTracking()
            }
            let invisible = isInvisible
            Task {
                await PresenceManager.shared.handleInvisibleModeChanged(invisible)
            }
        }
    }

    var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Keys.launchAtLogin) }
    }

    /// Whether window-title / browser-URL sharing exists in this build. Cut from the
    /// App Store build (v1); only compiled in with the DIRECT_DISTRIBUTION flag.
    static var isDetailedSharingAvailable: Bool {
        #if DIRECT_DISTRIBUTION
        return true
        #else
        return false
        #endif
    }

    /// Kept for UI compatibility. Defaults to false; ignored in the App Store build
    /// (v1 never sends window titles).
    var shareWindowTitle: Bool {
        didSet { defaults.set(shareWindowTitle, forKey: Keys.shareWindowTitle) }
    }

    /// Kept for UI compatibility. Defaults to false; ignored in the App Store build
    /// (v1 never sends browser domains).
    var shareBrowserURL: Bool {
        didSet { defaults.set(shareBrowserURL, forKey: Keys.shareBrowserURL) }
    }

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }

    // Nudge settings
    var nudgeShake: Bool {
        didSet { defaults.set(nudgeShake, forKey: Keys.nudgeShake) }
    }

    var nudgeSound: Bool {
        didSet { defaults.set(nudgeSound, forKey: Keys.nudgeSound) }
    }

    var nudgeNotification: Bool {
        didSet { defaults.set(nudgeNotification, forKey: Keys.nudgeNotification) }
    }

    private let defaults = UserDefaults.standard

    private init() {
        hiddenApps = defaults.stringArray(forKey: Keys.hiddenApps) ?? []
        isInvisible = defaults.bool(forKey: Keys.isInvisible)
        launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        #if DIRECT_DISTRIBUTION
        shareWindowTitle = defaults.object(forKey: Keys.shareWindowTitle) as? Bool ?? false
        shareBrowserURL = defaults.object(forKey: Keys.shareBrowserURL) as? Bool ?? false
        #else
        shareWindowTitle = false
        shareBrowserURL = false
        #endif
        hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
        // Nudge settings default to true for fun out-of-the-box experience
        nudgeShake = defaults.object(forKey: Keys.nudgeShake) as? Bool ?? true
        nudgeSound = defaults.object(forKey: Keys.nudgeSound) as? Bool ?? true
        nudgeNotification = defaults.object(forKey: Keys.nudgeNotification) as? Bool ?? true
    }
}

private enum Keys {
    static let hiddenApps = "hiddenApps"
    static let isInvisible = "isInvisible"
    static let launchAtLogin = "launchAtLogin"
    static let shareWindowTitle = "shareWindowTitle"
    static let shareBrowserURL = "shareBrowserURL"
    static let hasCompletedOnboarding = "hasCompletedOnboarding"
    static let nudgeShake = "nudgeShake"
    static let nudgeSound = "nudgeSound"
    static let nudgeNotification = "nudgeNotification"
}
