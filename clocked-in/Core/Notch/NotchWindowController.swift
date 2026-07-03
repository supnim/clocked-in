

import Foundation
import SwiftUI
import AppKit

// MARK: - NotchPanel (NSPanel subclass for proper floating behavior)

@MainActor
class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)

        // Panel-specific configuration
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false

        // Allows tooltips when app is inactive
        allowsToolTipsWhenApplicationIsInactive = true
    }
}

// MARK: - NotchWindowController

@MainActor
class NotchWindowController: NSWindowController {
    private let viewModel: NotchViewModel
    private var statusObservationTask: Task<Void, Never>?

    /// Window height derived from screen geometry
    private var windowHeight: CGFloat {
        viewModel.geometry.screenRect.height
    }

    init(viewModel: NotchViewModel) {
        self.viewModel = viewModel

        let screenFrame = viewModel.geometry.screenRect
        let height = screenFrame.height

        // Create NSPanel (not NSWindow) for proper floating behavior
        let panel = NotchPanel(
            contentRect: NSRect(
                x: screenFrame.origin.x,
                y: screenFrame.maxY - height,
                width: screenFrame.width,
                height: height
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Window configuration (matched to claude-island)
        panel.isOpaque = false
        panel.backgroundColor = NSColor.clear
        panel.hasShadow = false  // SwiftUI handles shadow
        panel.isMovable = false  // Prevents movement during space switches
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        panel.collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle
        ]
        panel.isMovableByWindowBackground = false
        panel.ignoresMouseEvents = true  // Default: clicks pass through

        // Set up content with pass-through hosting view
        let hostingView = PassThroughHostingView(rootView: NotchContentView(viewModel: viewModel))
        hostingView.hitTestRect = { [weak viewModel] in
            guard let vm = viewModel else { return .zero }
            return NotchGeometry.calculateHitTestRect(
                status: vm.status,
                openedSize: vm.openedSize,
                deviceNotchRect: vm.geometry.deviceNotchRect,
                screenWidth: vm.geometry.screenRect.width,
                windowHeight: height
            )
        }
        panel.contentView = hostingView

        super.init(window: panel)

        // Observe status changes for dynamic mouse event handling
        setupStatusObserver()

        // Boot animation after slight delay
        Task {
            try? await Task.sleep(for: .seconds(0.3))
            self.viewModel.notchPop()
        }
    }

    private func setupStatusObserver() {
        statusObservationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }

                // Wait for status to change
                await withCheckedContinuation { continuation in
                    withObservationTracking {
                        _ = self.viewModel.status
                    } onChange: {
                        continuation.resume()
                    }
                }

                // Handle the new status
                guard let panel = self.window as? NotchPanel else { continue }
                let status = self.viewModel.status
                switch status {
                case .opened:
                    panel.ignoresMouseEvents = false
                    if self.viewModel.openReason != .notification {
                        NSApp.activate(ignoringOtherApps: false)
                        panel.makeKey()
                    }
                case .closed, .popping:
                    panel.ignoresMouseEvents = true
                }
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

}

// MARK: - PassThroughHostingView (Click-through with dynamic hit testing)

class PassThroughHostingView<Content: View>: NSHostingView<Content> {
    /// Closure that returns the current hit-testable rect
    var hitTestRect: () -> CGRect = { .zero }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Only accept hits within the dynamic panel rect
        guard hitTestRect().contains(point) else {
            return nil  // Pass through to windows behind
        }
        return super.hitTest(point)
    }
}
