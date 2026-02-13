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
        // Empty scene - all UI handled by AppDelegate
        Settings {
            EmptyView()
        }
    }
}
