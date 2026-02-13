import AppKit
import SwiftUI
import OSLog

class AppDelegate: NSObject, NSApplicationDelegate {
    private var notchWindowController: NotchWindowController?
    private let log = Logger(subsystem: "clocked-in", category: "lifecycle")

    func applicationDidFinishLaunching(_ notification: Notification) {
        log.info("Clocked-In app did finish launching")

        // Set up error handler callbacks
        setupErrorHandling()

        // Set up the notch UI
        setupNotch()

        // Handle authentication state
        setupAuthStateHandling()
    }

    private func setupErrorHandling() {
        // Handle auth failures (401 errors, expired tokens)
        ErrorHandler.shared.onAuthFailure = { [weak self] in
            self?.log.warning("Authentication failure detected, signing out")
            AuthManager.shared.signOut()
            self?.stopServices()
            self?.showOnboarding()
        }
    }

    private func setupNotch() {
        guard let screen = NSScreen.main else { return }

        let geometry = NotchGeometry.create(for: screen)
        let viewModel = NotchViewModel(geometry: geometry)

        notchWindowController = NotchWindowController(viewModel: viewModel)
        notchWindowController?.showWindow(nil)
    }

    private func setupAuthStateHandling() {
        // Check if user is authenticated
        if AuthManager.shared.isAuthenticated {
            startServices()
        } else {
            // Show onboarding/sign-in
            showOnboarding()
        }
    }

    private func startServices() {
        PresenceManager.shared.startPresence()
        PresenceListener.shared.startListening()
        IdleDetector.shared.start()
    }

    private func stopServices() {
        IdleDetector.shared.stop()
        PresenceManager.shared.stopPresence()
        PresenceListener.shared.stopListening()
    }

    private func showOnboarding() {
        let onboardingView = OnboardingView()
        let window = createWindow(
            content: onboardingView,
            title: "Welcome to Clocked-In",
            size: NSSize(width: 400, height: 500)
        )
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
        stopServices()
        log.info("Clocked-In app will terminate")
    }

    // Handle deep links (including OAuth callback)
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            DeepLinkHandler.shared.handle(url: url)
            log.info("Received deep link: \(url)")
        }
    }
}
