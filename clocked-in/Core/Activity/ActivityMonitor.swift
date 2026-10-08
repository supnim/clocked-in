import Foundation
import SwiftUI
import AppKit

@MainActor
@Observable
final class ActivityMonitor {
    @ObservationIgnored
    nonisolated(unsafe) private var debounceTask: Task<Void, Never>?

    var currentActivity: Activity?

    init() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleAppChange(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        // Report whatever is frontmost right now (no activation notification for it)
        if let app = NSWorkspace.shared.frontmostApplication {
            scheduleActivityUpdate(
                bundleId: app.bundleIdentifier ?? "",
                appName: app.localizedName ?? "Unknown",
                pid: app.processIdentifier
            )
        }
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        debounceTask?.cancel()
    }

    @objc nonisolated private func handleAppChange(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }

        // Extract Sendable values before hopping to the MainActor
        let bundleId = app.bundleIdentifier ?? ""
        let appName = app.localizedName ?? "Unknown"
        let pid = app.processIdentifier

        Task { @MainActor [weak self] in
            self?.scheduleActivityUpdate(bundleId: bundleId, appName: appName, pid: pid)
        }
    }

    private func scheduleActivityUpdate(bundleId: String, appName: String, pid: pid_t) {
        // Ignore ourselves (opening the notch activates Clocked-In). Keep the previous
        // activity and any pending debounce for the app the user was actually in.
        if Self.isOwnApp(bundleId: bundleId, pid: pid) {
            return
        }

        // Cancel previous debounce
        debounceTask?.cancel()

        // Debounce 2 seconds
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.publishActivity(bundleId: bundleId, appName: appName, pid: pid)
        }
    }

    private func publishActivity(bundleId: String, appName: String, pid: pid_t) async {
        // Re-fetch the app on the MainActor (NSRunningApplication isn't Sendable)
        let runningApp = NSRunningApplication(processIdentifier: pid)
        let iconData = Self.iconPNGData(for: runningApp?.icon)

        #if DIRECT_DISTRIBUTION
        let windowTitle = AppSettings.shared.shareWindowTitle ? Self.windowTitle(forPID: pid) : nil
        let browserURL = AppSettings.shared.shareBrowserURL ? BrowserURLFetcher.getCurrentURL(for: bundleId) : nil
        let browserDomain = browserURL.flatMap { URL(string: $0)?.host }
        #else
        // v1 App Store build: window titles and browser URLs are never collected
        let windowTitle: String? = nil
        let browserURL: String? = nil
        let browserDomain: String? = nil
        #endif

        let activity = Activity(
            appName: appName,
            bundleId: bundleId,
            windowTitle: windowTitle,
            browserURL: browserURL,
            browserDomain: browserDomain,
            browserTitle: nil,
            appIcon: iconData,
            timestamp: Date()
        )

        currentActivity = activity

        // Notify presence manager of activity change (syncs to backend)
        await PresenceManager.shared.updatePresence(for: activity)
    }

    // MARK: - Helpers

    static func isOwnApp(bundleId: String, pid: pid_t) -> Bool {
        if pid == ProcessInfo.processInfo.processIdentifier { return true }
        if let ownBundleId = Bundle.main.bundleIdentifier, bundleId == ownBundleId { return true }
        return false
    }

    /// Renders an app icon to a small PNG (32×32 px). Returns nil if the PNG's base64
    /// form would exceed `PresencePayload.maxIconBase64Length` (16 KB).
    static func iconPNGData(for image: NSImage?, pixelSize: Int = 32) -> Data? {
        guard let image else { return nil }

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        bitmap.size = NSSize(width: pixelSize, height: pixelSize)

        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        image.draw(
            in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
            from: .zero,
            operation: .copy,
            fraction: 1.0
        )
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        guard let png = bitmap.representation(using: .png, properties: [:]) else { return nil }
        guard png.base64EncodedString().count <= PresencePayload.maxIconBase64Length else { return nil }
        return png
    }

    #if DIRECT_DISTRIBUTION
    /// Requires Screen Recording permission; not available in the App Store build.
    private static func windowTitle(forPID pid: pid_t) -> String? {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        for window in windowList {
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? Int,
                  ownerPID == Int(pid),
                  let windowName = window[kCGWindowName as String] as? String,
                  !windowName.isEmpty else { continue }
            return windowName
        }
        return nil
    }
    #endif
}
