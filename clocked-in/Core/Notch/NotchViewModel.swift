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

    let geometry: NotchGeometry

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
        let addFriendObserver = NotificationCenter.default.addObserver(
            forName: DeepLinkHandler.addFriendNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let username = notification.userInfo?["username"] as? String else { return }
            MainActor.assumeIsolated {
                _ = username  // Username available for pre-filling AddFriendView if needed
                self?.showContent(.addFriend)
            }
        }
        deepLinkObservers.append(addFriendObserver)

        let inviteCodeObserver = NotificationCenter.default.addObserver(
            forName: DeepLinkHandler.inviteCodeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let _ = notification.userInfo?["code"] as? String else { return }
            MainActor.assumeIsolated {
                self?.showContent(.addFriend)
            }
        }
        deepLinkObservers.append(inviteCodeObserver)
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

                // Escape closes the notch
                if event.keyCode == 53, self.status == .opened {
                    self.notchClose()
                    return true
                }

                // Cmd shortcuts
                if event.modifierFlags.contains(.command) {
                    switch event.keyCode {
                    case 12:  // Cmd+Q
                        NSApp.terminate(nil); return true
                    case 13:  // Cmd+W
                        if self.status == .opened { self.notchClose(); return true }
                    case 43:  // Cmd+,
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
            if contentType == .usernamePicker {
                return
            }

            if geometry.isPointOutsidePanel(location, size: openedSize) {
                notchClose()
                repostClickAt(location)
            } else if geometry.notchScreenRect.contains(location) {
                notchClose()
            }
        case .closed, .popping:
            if geometry.isPointInNotch(location) {
                notchOpen(reason: .click)
            }
        }
    }

    private func repostClickAt(_ location: CGPoint) {
        Task {
            try? await Task.sleep(for: .seconds(0.05))
            guard let screen = NSScreen.main else { return }
            let screenHeight = screen.frame.height
            let cgPoint = CGPoint(x: location.x, y: screenHeight - location.y)

            if let mouseDown = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseDown,
                mouseCursorPosition: cgPoint,
                mouseButton: .left
            ) {
                mouseDown.post(tap: .cghidEventTap)
            }

            if let mouseUp = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseUp,
                mouseCursorPosition: cgPoint,
                mouseButton: .left
            ) {
                mouseUp.post(tap: .cghidEventTap)
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
        openReason = reason
        withAnimation(openAnimation) {
            status = .opened
        }
    }

    func notchClose() {
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
            guard !Task.isCancelled else { return }
            notchClose()
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
            guard !Task.isCancelled else { return }
            quickPopNotification = nil
            notchClose()
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
        contentType = .lobby
        if status == .opened {
            notchClose()
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

    private func needsUsernameSetup() -> Bool {
        guard let user = AuthManager.shared.currentUser else {
            return false
        }
        return user.username.isEmpty
    }
}
