//
//  clocked_inApp.swift
//  clocked-in
//
//  Created by Nimesh on 03/12/2025.
//

import SwiftUI

@main
struct ClockedInApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .frame(width: 400, height: 500)
        }
        .commands {
            TextEditingCommands()
            CommandGroup(replacing: .appInfo) {
                Button("About Clocked-In") {
                    NSApplication.shared.orderFrontStandardAboutPanel(nil)
                }
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .appTermination) {
                Button("Quit Clocked-In") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }
    }
}
