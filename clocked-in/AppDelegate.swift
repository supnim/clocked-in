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
    private weak var aboutWindow: NSWindow?
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
        statusItem.button?.title = viewModel.displayText
        statusItem.button?.toolTip = viewModel.tooltipText
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

        let aboutItem = NSMenuItem(title: "About Clocked In", action: #selector(openAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

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

    @objc private func openAbout() {
        if let window = aboutWindow {
            window.makeKeyAndOrderFront(nil)
        } else {
            let window = NSWindow(contentViewController: NSHostingController(rootView: AboutView()))
            window.title = "About Clocked In"
            window.styleMask = [.titled, .closable]
            window.center()
            window.delegate = self
            aboutWindow = window
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
        } else {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "Settings"
            window.styleMask = [.titled, .closable]
            window.center()
            window.delegate = self
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

        let window = NSWindow(contentViewController: NSHostingController(rootView: onboardingView))
        window.title = "Welcome to Clocked In"
        window.styleMask = [.titled, .closable]
        window.center()
        window.delegate = self
        onboardingWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        observationTask?.cancel()
        observationTask = nil
    }
}
