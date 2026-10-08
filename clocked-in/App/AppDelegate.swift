import AppKit
import SwiftUI
import OSLog

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var notchWindowController: NotchWindowController?
    private let log = Logger(subsystem: "clocked-in", category: "lifecycle")

    private var onboardingWindow: NSWindow?

    /// Set when onboarding completes so closing the window doesn't quit the app.
    private var isClosingOnboardingProgrammatically = false

    /// Owned here; feeds PresenceManager on app switches. Nil while services are stopped.
    private var activityMonitor: ActivityMonitor?

    private var servicesRunning = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        log.info("Clocked-In app did finish launching")

        // Set up error handler / auth callbacks
        setupErrorHandling()
        setupAuthCallbacks()

        // Set up the notch UI
        setupNotch()

        // Restore the saved session BEFORE deciding onboarding vs services
        Task { @MainActor in
            await AuthManager.shared.restoreSession()
            self.routeAfterAuthChange()
        }
    }

    private func setupErrorHandling() {
        // Handle auth failures (401 errors that silent re-auth couldn't fix)
        ErrorHandler.shared.onAuthFailure = { [weak self] in
            self?.log.warning("Authentication failure detected, signing out")
            AuthManager.shared.handleAuthFailure()
        }
    }

    private func setupAuthCallbacks() {
        AuthManager.shared.onWillEndSession = { [weak self] in
            await self?.stopServices()
        }
        AuthManager.shared.onDidEndSession = { [weak self] in
            guard let self else { return }
            self.notchWindowController?.resetForSignedOut()
            self.showOnboarding()
        }
    }

    private func setupNotch() {
        guard let screen = NotchGeometry.preferredScreen() else { return }

        let geometry = NotchGeometry.create(for: screen)
        let viewModel = NotchViewModel(geometry: geometry)

        notchWindowController = NotchWindowController(viewModel: viewModel)
        notchWindowController?.showWindow(nil)
    }

    /// Starts services if fully signed in (token + username), otherwise shows onboarding.
    private func routeAfterAuthChange() {
        let auth = AuthManager.shared
        if auth.isAuthenticated && auth.hasUsername {
            startServices()
        } else {
            // Keep the notch inert (no hover/click tracking) until setup finishes
            EventMonitors.shared.stop()
            showOnboarding()
        }
    }

    // MARK: - Services

    /// Idempotent: safe to call more than once.
    private func startServices() {
        guard !servicesRunning else { return }
        guard let token = AuthManager.shared.currentAuthToken else {
            log.warning("startServices called without an auth token")
            return
        }
        servicesRunning = true
        log.info("Starting services")

        // Global mouse tracking for the notch
        EventMonitors.shared.start()

        // Friend presence listener (AppDelegate is the only owner)
        PresenceListener.shared.startListening()

        // Real-time connection
        WebSocketClient.shared.connect(token: token)

        PresenceManager.shared.startPresence()

        // Activity detection → PresenceManager.updatePresence(for:)
        if activityMonitor == nil {
            activityMonitor = ActivityMonitor()
        }

        IdleDetector.shared.start()
    }

    /// Idempotent: safe to call when services aren't running.
    private func stopServices() async {
        guard servicesRunning else { return }
        servicesRunning = false
        log.info("Stopping services")

        activityMonitor = nil
        IdleDetector.shared.stop()

        // Tell friends we're gone while the socket is still open
        await WebSocketClient.shared.sendGoOffline()
        PresenceManager.shared.stopPresence()
        PresenceManager.shared.clearPendingUpdates()

        PresenceListener.shared.stopListening()
        WebSocketClient.shared.disconnect()
        EventMonitors.shared.stop()
    }

    // MARK: - Onboarding

    private func showOnboarding() {
        // Reuse existing onboarding window if one is already open
        if let existing = onboardingWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // After a user-initiated sign-out / deletion, wait for the user to sign in again
        // (auto-registering would sign straight back in / create a new account).
        let onboardingView = OnboardingView(
            onFinished: { [weak self] in
                self?.finishOnboarding()
            },
            autoRegister: !AuthManager.shared.requiresExplicitSignIn
        )
        let window = createWindow(
            content: onboardingView,
            title: "Welcome to Clocked-In",
            size: NSSize(width: 400, height: 500)
        )
        window.isReleasedWhenClosed = false
        window.delegate = self
        onboardingWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finishOnboarding() {
        AppSettings.shared.hasCompletedOnboarding = true

        if let window = onboardingWindow {
            isClosingOnboardingProgrammatically = true
            window.close()
            isClosingOnboardingProgrammatically = false
        }
        onboardingWindow = nil

        startServices()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === onboardingWindow else { return }
        onboardingWindow = nil

        // Closing setup before finishing leaves the app unusable (no Dock icon), so quit.
        if !isClosingOnboardingProgrammatically && !servicesRunning {
            log.info("Onboarding window closed before setup finished; quitting")
            NSApp.terminate(nil)
        }
    }

    private func createWindow<Content: View>(content: Content, title: String, size: NSSize) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.center()

        let hostingView = NSHostingView(rootView: content)
        window.contentView = hostingView

        return window
    }

    func applicationWillTerminate(_ notification: Notification) {
        var finished = false
        Task { @MainActor in
            await self.stopServices()
            finished = true
        }
        let deadline = Date().addingTimeInterval(2)
        while !finished && Date() < deadline {
            CFRunLoopRunInMode(.defaultMode, 0.1, false)
        }

        log.info("Clocked-In app will terminate")
    }

    // Handle deep links
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            DeepLinkHandler.shared.handle(url: url)
            log.info("Received deep link: \(url)")
        }
    }
}
