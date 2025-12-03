//
//  Settings.swift
//  clocked-in
//
//  Created by Nimesh on 03/12/2025.
//

import Foundation
import SwiftUI

enum ViewMode: String, CaseIterable, Codable {
    case day = "Day"
    case week = "Week"
    case month = "Month"
    case year = "Year"

    func next() -> ViewMode {
        let all = ViewMode.allCases
        let currentIndex = all.firstIndex(of: self)!
        let nextIndex = (currentIndex + 1) % all.count
        return all[nextIndex]
    }
}

enum WeekMode: String, CaseIterable, Codable {
    case fullWeek = "Mon-Sun (7 days)"
    case workingDays = "Working days only (Mon-Fri)"
}

enum CalendarMode: String, CaseIterable, Codable {
    case allDays = "All days"
    case workingDays = "Working days only"
}

enum UnitDisplayMode: String, CaseIterable, Codable {
    case words = "Words"
    case icons = "Icons"
    case none = "None"
}

@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    // Keys
    private enum Keys {
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let dayStartHour = "dayStartHour"
        static let dayStartMinute = "dayStartMinute"
        static let dayEndHour = "dayEndHour"
        static let dayEndMinute = "dayEndMinute"
        static let currentViewMode = "currentViewMode"
        static let weekMode = "weekMode"
        static let monthYearMode = "monthYearMode"
        static let launchAtLogin = "launchAtLogin"
        static let unitDisplayMode = "unitDisplayMode"
    }

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }

    var dayStartHour: Int {
        didSet { defaults.set(dayStartHour, forKey: Keys.dayStartHour) }
    }

    var dayStartMinute: Int {
        didSet { defaults.set(dayStartMinute, forKey: Keys.dayStartMinute) }
    }

    var dayEndHour: Int {
        didSet { defaults.set(dayEndHour, forKey: Keys.dayEndHour) }
    }

    var dayEndMinute: Int {
        didSet { defaults.set(dayEndMinute, forKey: Keys.dayEndMinute) }
    }

    var currentViewMode: ViewMode {
        didSet {
            if let encoded = try? JSONEncoder().encode(currentViewMode) {
                defaults.set(encoded, forKey: Keys.currentViewMode)
            }
        }
    }

    var weekMode: WeekMode {
        didSet {
            if let encoded = try? JSONEncoder().encode(weekMode) {
                defaults.set(encoded, forKey: Keys.weekMode)
            }
        }
    }

    var monthYearMode: CalendarMode {
        didSet {
            if let encoded = try? JSONEncoder().encode(monthYearMode) {
                defaults.set(encoded, forKey: Keys.monthYearMode)
            }
        }
    }

    var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Keys.launchAtLogin) }
    }

    var unitDisplayMode: UnitDisplayMode {
        didSet {
            if let encoded = try? JSONEncoder().encode(unitDisplayMode) {
                defaults.set(encoded, forKey: Keys.unitDisplayMode)
            }
        }
    }

    // Computed properties
    var dayStartDate: Date {
        get {
            Calendar.current.date(bySettingHour: dayStartHour, minute: dayStartMinute, second: 0, of: Date()) ?? Date()
        }
        set {
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            dayStartHour = components.hour ?? 9
            dayStartMinute = components.minute ?? 0
        }
    }

    var dayEndDate: Date {
        get {
            Calendar.current.date(bySettingHour: dayEndHour, minute: dayEndMinute, second: 0, of: Date()) ?? Date()
        }
        set {
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            dayEndHour = components.hour ?? 17
            dayEndMinute = components.minute ?? 0
        }
    }

    var workdayDurationMinutes: Int {
        (dayEndHour * 60 + dayEndMinute) - (dayStartHour * 60 + dayStartMinute)
    }

    var minutesPerPercent: Double {
        Double(workdayDurationMinutes) / 100.0
    }

    private init() {
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
        self.dayStartHour = defaults.object(forKey: Keys.dayStartHour) as? Int ?? 9
        self.dayStartMinute = defaults.object(forKey: Keys.dayStartMinute) as? Int ?? 0
        self.dayEndHour = defaults.object(forKey: Keys.dayEndHour) as? Int ?? 17
        self.dayEndMinute = defaults.object(forKey: Keys.dayEndMinute) as? Int ?? 0
        self.launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)

        if let data = defaults.data(forKey: Keys.currentViewMode),
           let decoded = try? JSONDecoder().decode(ViewMode.self, from: data) {
            self.currentViewMode = decoded
        } else {
            self.currentViewMode = .day
        }

        if let data = defaults.data(forKey: Keys.weekMode),
           let decoded = try? JSONDecoder().decode(WeekMode.self, from: data) {
            self.weekMode = decoded
        } else {
            self.weekMode = .fullWeek
        }

        if let data = defaults.data(forKey: Keys.monthYearMode),
           let decoded = try? JSONDecoder().decode(CalendarMode.self, from: data) {
            self.monthYearMode = decoded
        } else {
            self.monthYearMode = .allDays
        }

        if let data = defaults.data(forKey: Keys.unitDisplayMode),
           let decoded = try? JSONDecoder().decode(UnitDisplayMode.self, from: data) {
            self.unitDisplayMode = decoded
        } else {
            self.unitDisplayMode = .words
        }
    }
}
