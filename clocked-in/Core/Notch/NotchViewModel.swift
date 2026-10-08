import AppKit
import Combine
import SwiftUI

enum NotchStatus {
    case closed, opened, popping
}

enum NotchOpenReason {
    case click, hover, notification, boot
}

@MainActor
@Observable
class NotchViewModel {
    var status: NotchStatus = .closed
    var openReason: NotchOpenReason = .boot
    var contentType: NotchContentType = .lobby
    var isHovering = false
    var quickPopNotification: FriendActivityNotification?

    // Dynamic height support
    var isExpanded: Bool = false

    /// Username from a `clockedin://add/{username}` deep link, consumed by AddFriendView.
    var pendingAddFriendUsername: String?

    private let events = EventMonitors.shared
    private var cancellables = Set<AnyCancellable>()

    @ObservationIgnored
    private var hoverTask: Task<Void, Never>?
    @ObservationIgnored
    private var popDismissTask: Task<Void, Never>?
    @ObservationIgnored
    private var quickPopTask: Task<Void, Never>?
    @ObservationIgnored
    private var keyMonitor: Any?

    private let hoverDelay: TimeInterval = 1.0

    /// Rebuilt by NotchWindowController when screens change.
    var geometry: NotchGeometry

    @ObservationIgnored
    private var deepLinkObservers: [NSObjectProtocol] = []

    init(geometry: NotchGeometry, installMonitors: Bool = true) {
        self.geometry = geometry
        guard installMonitors else { return }
        setupEventHandlers()
        setupKeyboardMonitor()
        setupDeepLinkObservers()
    }

    isolated deinit {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        for observer in deepLinkObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Deep Link Observers

    private func setupDeepLinkObservers() {
        // Posted by DeepLinkHandler for clockedin://add/{username}. userInfo["username"]: String
        let addFriendObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("openAddFriend"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let raw = notification.userInfo?["username"] as? String
            MainActor.assumeIsolated {
                self?.openAddFriend(prefilledUsername: raw)
            }
        }
        deepLinkObservers.append(addFriendObserver)
    }

    /// Opens the Add Friend screen, optionally pre-filled with a (sanitised) username.
    func openAddFriend(prefilledUsername raw: String?) {
        guard AuthManager.shared.isAuthenticated, !isUsernameRequired else { return }
        if let raw {
            let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789_")
            let cleaned = String(raw.lowercased().filter { allowed.contains($0) }.prefix(20))
            pendingAddFriendUsername = cleaned.isEmpty ? nil : cleaned
        }
        showContent(.addFriend)
    }

    // MARK: - Sizes

    var openedSize: CGSize {
        let screenHeight = geometry.screenRect.height
        let maxHeight = min(screenHeight * 0.6, 700)
        let baseWidth = min(geometry.screenRect.width * 0.4, 480)
        let baseHeight: CGFloat = switch contentType {
        case .usernamePicker: min(280, maxHeight)
        case .lobby: min(isExpanded ? 800 : 320, maxHeight)
        case .settings: min(420, maxHeight)
        case .addFriend: min(400, maxHeight)
        case .pendingRequests: min(360, maxHeight)
        case .friendDetail: min(360, maxHeight)
        }

        return CGSize(width: baseWidth, height: baseHeight)
    }

    // MARK: - Keyboard Monitor

    private func setupKeyboardMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // NSEvent isn't Sendable, so we can't return it from `assumeIsolated`
            // (its result type must be Sendable). Decide whether to swallow the
            // event on the main actor, then apply that decision out here.
            let shouldSwallow = MainActor.assumeIsolated { () -> Bool in
                guard let self else { return false }

                // Escape closes the notch (unless a username is still required)
                if event.keyCode == 53, self.status == .opened, !self.isUsernameRequired {
                    self.notchClose()
                    return true
                }

                // Cmd shortcuts
                if event.modifierFlags.contains(.command) {
                    switch event.keyCode {
                    case 12:  // Cmd+Q
                        NSApp.terminate(nil); return true
                    case 13:  // Cmd+W
                        if self.status == .opened, !self.isUsernameRequired { self.notchClose(); return true }
                    case 43:  // Cmd+,
                        guard !self.isUsernameRequired else { return true }
                        self.showContent(.settings); return true
                    default: break
                    }
                }

                return false
            }

            return shouldSwallow ? nil : event
        }
    }

    // MARK: - Event Handlers

    private func setupEventHandlers() {
        events.mouseLocation
            .throttle(for: .milliseconds(50), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] location in
                self?.handleMouseMove(location)
            }
            .store(in: &cancellables)

        events.mouseDown
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleMouseDown()
            }
            .store(in: &cancellables)
    }

    private func handleMouseMove(_ location: CGPoint) {
        let inNotch = geometry.isPointInNotch(location)
        let inOpened = status == .opened && geometry.isPointInOpenedPanel(location, size: openedSize)
        let newHovering = inNotch || inOpened

        guard newHovering != isHovering else { return }
        isHovering = newHovering

        hoverTask?.cancel()
        hoverTask = nil

        if isHovering && (status == .closed || status == .popping) {
            hoverTask = Task {
                try? await Task.sleep(for: .seconds(hoverDelay))
                guard !Task.isCancelled, self.isHovering else { return }
                self.notchOpen(reason: .hover)
            }
        }
    }

    private func handleMouseDown() {
        let location = NSEvent.mouseLocation

        switch status {
        case .opened:
            // Prevent closing if username picker is shown and no username set
            if isUsernameRequired {
                return
            }

            if geometry.isPointOutsidePanel(location, size: openedSize) {
                // Just close; the click already reached whatever is underneath
                // (the panel ignores mouse events outside its hit-test rect).
                notchClose()
            } else if geometry.notchScreenRect.contains(location) {
                notchClose()
            }
        case .closed, .popping:
            if geometry.isPointInNotch(location) {
                notchOpen(reason: .click)
            }
        }
    }

    // MARK: - Animation Constants (matched to claude-island)

    private let openAnimation = Animation.spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
    private let closeAnimation = Animation.spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)
    private let popAnimation = Animation.spring(response: 0.4, dampingFraction: 0.6, blendDuration: 0)
    private let bootDuration: TimeInterval = 1.0

    // MARK: - State Transitions

    func notchOpen(reason: NotchOpenReason) {
        // Opening supersedes any pending boot-pop / quick-pop auto-dismiss
        popDismissTask?.cancel()
        popDismissTask = nil
        quickPopTask?.cancel()
        quickPopTask = nil
        quickPopNotification = nil

        openReason = reason
        withAnimation(openAnimation) {
            status = .opened
        }
    }

    func notchClose() {
        guard !isUsernameRequired else { return }
        withAnimation(closeAnimation) {
            status = .closed
        }
    }

    func notchPop() {
        withAnimation(popAnimation) {
            status = .popping
        }

        popDismissTask?.cancel()
        popDismissTask = Task {
            try? await Task.sleep(for: .seconds(bootDuration))
            guard !Task.isCancelled, self.status == .popping else { return }
            self.notchClose()
        }
    }

    func notchUnpop() {
        guard status == .popping else { return }
        popDismissTask?.cancel()
        popDismissTask = nil
        status = .closed
    }

    func notchQuickPop(notification: FriendActivityNotification) {
        guard status == .closed else { return }
        quickPopNotification = notification
        withAnimation(popAnimation) {
            status = .popping
        }
        quickPopTask?.cancel()
        quickPopTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, self.status == .popping else { return }
            self.quickPopNotification = nil
            self.notchClose()
        }
    }

    func showContent(_ type: NotchContentType) {
        contentType = type
        if status == .closed {
            notchOpen(reason: .click)
        }
    }

    // MARK: - Username Setup

    func initializeContentType() {
        if needsUsernameSetup() {
            contentType = .usernamePicker
            if status == .closed {
                notchOpen(reason: .boot)
            }
        } else {
            contentType = .lobby
        }
    }

    func onUsernameSetupComplete() {
        usernameJustClaimed = true
        contentType = .lobby
        if status == .opened {
            notchClose()
        }
        // Pull the claimed username into AuthManager.currentUser
        Task {
            await AuthManager.shared.refreshCurrentUser()
        }
    }

    // MARK: - Dynamic Height

    func toggleExpanded() {
        guard contentType == .lobby && status == .opened else { return }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isExpanded.toggle()
        }
    }

    var expandButtonTitle: String {
        isExpanded ? "▲ Less" : "▼ More"
    }

    /// Set once the in-notch picker succeeds, until AuthManager's currentUser catches up.
    @ObservationIgnored
    private var usernameJustClaimed = false

    private func needsUsernameSetup() -> Bool {
        guard AuthManager.shared.currentUser != nil, !usernameJustClaimed else {
            return false
        }
        return !AuthManager.shared.hasUsername
    }

    /// True while the username picker is showing and the user still has no username.
    /// Esc / Cmd+W / close buttons / outside clicks must not dismiss it.
    var isUsernameRequired: Bool {
        contentType == .usernamePicker && needsUsernameSetup()
    }

    /// Returns the notch to its idle state (used after sign-out / account deletion).
    func resetForSignedOut() {
        hoverTask?.cancel()
        hoverTask = nil
        popDismissTask?.cancel()
        popDismissTask = nil
        quickPopTask?.cancel()
        quickPopTask = nil
        quickPopNotification = nil
        pendingAddFriendUsername = nil
        usernameJustClaimed = false
        isExpanded = false
        contentType = .lobby
        withAnimation(closeAnimation) {
            status = .closed
        }
    }
}
