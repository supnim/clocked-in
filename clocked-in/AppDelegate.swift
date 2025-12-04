//
//  AppDelegate.swift
//  clocked-in
//
//  Created by Nimesh on 03/12/2025.
//

import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var viewModel: MenuBarViewModel!
    private weak var settingsWindow: NSWindow?
    private weak var onboardingWindow: NSWindow?
    private var observationTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        viewModel = MenuBarViewModel()

        setupStatusItem()
        setupObservation()

        if !AppSettings.shared.hasCompletedOnboarding {
            showOnboarding()
        } else {
            viewModel.startTimer()
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.title = viewModel.displayText
            button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    private func setupObservation() {
        observationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.updateStatusItem()

            while !Task.isCancelled {
                await withCheckedContinuation { continuation in
                    withObservationTracking {
                        _ = self.viewModel.displayText
                        _ = self.viewModel.tooltipText
                        _ = self.viewModel.currentPercentage
                        _ = self.viewModel.isOvertime
                        _ = self.viewModel.displayStyle
                        _ = self.viewModel.textDetail
                        _ = self.viewModel.visualDetail
                        _ = self.viewModel.accentColor
                        _ = self.viewModel.weekMode
                        _ = self.viewModel.monthYearMode
                    } onChange: {
                        continuation.resume()
                    }
                }
                guard !Task.isCancelled else { break }
                self.updateStatusItem()
            }
        }
    }

    private func updateStatusItem() {
        let result = StatusBarRenderer.render(
            percentage: viewModel.currentPercentage,
            mode: viewModel.currentMode,
            settings: AppSettings.shared,
            isOvertime: viewModel.isOvertime
        )

        if let button = statusItem.button {
            // Handle visual display styles (pie, bar, gauge)
            if let image = result.image {
                button.image = image
                button.imagePosition = .imageLeading

                if let title = result.title {
                    button.title = " \(title)"  // Space for visual separation
                } else {
                    button.title = ""
                }
            } else {
                // Text-only mode
                button.image = nil
                button.title = viewModel.displayText
            }

            button.toolTip = viewModel.tooltipText
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            showMenu()
        } else {
            viewModel.cycleMode()
        }
    }

    private func showMenu() {
        let menu = NSMenu()

        let viewItem = NSMenuItem(title: "View: \(viewModel.currentMode.rawValue)", action: nil, keyEquivalent: "")
        viewItem.isEnabled = false
        menu.addItem(viewItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Clocked In", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
        } else {
            let window = createGlassWindow(
                content: SettingsView(),
                title: "Clocked In",
                size: NSSize(width: 420, height: 680)
            )
            settingsWindow = window
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showOnboarding() {
        let onboardingView = OnboardingView()
            .onDisappear { [weak self] in
                self?.viewModel.updateDisplay()
                self?.viewModel.startTimer()
            }

        let window = createGlassWindow(
            content: onboardingView,
            title: "Welcome to Clocked In",
            size: NSSize(width: 420, height: 580)
        )
        onboardingWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func createGlassWindow<Content: View>(content: Content, title: String, size: NSSize) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.center()
        window.delegate = self

        // Create visual effect view for glass background
        let visualEffectView = NSVisualEffectView()
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.material = .sidebar  // Provides translucent glass effect

        // Host the SwiftUI content
        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        visualEffectView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
            hostingView.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor),
            hostingView.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor)
        ])

        window.contentView = visualEffectView

        return window
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        observationTask?.cancel()
        observationTask = nil
    }
}
