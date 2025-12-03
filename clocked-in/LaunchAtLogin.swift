//
//  LaunchAtLogin.swift
//  clocked-in
//
//  Created by Nimesh on 03/12/2025.
//

import ServiceManagement

@MainActor
enum LaunchAtLogin {
    enum Error: LocalizedError {
        case registrationFailed(Swift.Error)
        case unregistrationFailed(Swift.Error)

        var errorDescription: String? {
            switch self {
            case .registrationFailed(let error):
                return "Failed to enable launch at login: \(error.localizedDescription)"
            case .unregistrationFailed(let error):
                return "Failed to disable launch at login: \(error.localizedDescription)"
            }
        }
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            throw enabled ? Error.registrationFailed(error) : Error.unregistrationFailed(error)
        }
    }
}
