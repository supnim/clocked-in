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

// MARK: - Display Settings (Two-Tier Model)

/// Primary display style choice
enum DisplayStyle: String, CaseIterable, Codable {
    case text = "Text"
    case pie = "Pie"
    case bar = "Bar"
    case gauge = "Gauge"

    var isVisual: Bool {
        self != .text
    }
}

/// Detail level for text display style
enum TextDetail: String, CaseIterable, Codable {
    case full = "Full"        // "Day 42%"
    case compact = "Compact"  // "D 42%"
    case minimal = "Minimal"  // "42%"

    var example: String {
        switch self {
        case .full: return "Day 42%"
        case .compact: return "D 42%"
        case .minimal: return "42%"
        }
    }
}

/// Detail level for visual display styles (pie, bar, gauge)
enum VisualDetail: String, CaseIterable, Codable {
    case withPercent = "With %"
    case visualOnly = "Visual Only"

    var example: String {
        switch self {
        case .withPercent: return "[visual] 42%"
        case .visualOnly: return "[visual]"
        }
    }
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
        static let displayStyle = "displayStyle"
        static let textDetail = "textDetail"
        static let visualDetail = "visualDetail"
        static let accentColorData = "accentColorData"
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

    var displayStyle: DisplayStyle {
        didSet {
            if let encoded = try? JSONEncoder().encode(displayStyle) {
                defaults.set(encoded, forKey: Keys.displayStyle)
            }
        }
    }

    var textDetail: TextDetail {
        didSet {
            if let encoded = try? JSONEncoder().encode(textDetail) {
                defaults.set(encoded, forKey: Keys.textDetail)
            }
        }
    }

    var visualDetail: VisualDetail {
        didSet {
            if let encoded = try? JSONEncoder().encode(visualDetail) {
                defaults.set(encoded, forKey: Keys.visualDetail)
            }
        }
    }

    var accentColor: Color {
        didSet {
            if let data = accentColor.toData() {
                defaults.set(data, forKey: Keys.accentColorData)
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
            let newStartHour = components.hour ?? 9
            let newStartMinute = components.minute ?? 0

            // Validate: ensure new start time is before end time
            let newStartMinutes = newStartHour * 60 + newStartMinute
            let currentEndMinutes = dayEndHour * 60 + dayEndMinute

            if newStartMinutes >= currentEndMinutes {
                // Adjust end time to be at least 1 hour after new start time
                let adjustedEndMinutes = newStartMinutes + 60
                dayEndHour = (adjustedEndMinutes / 60) % 24
                dayEndMinute = adjustedEndMinutes % 60
            }

            dayStartHour = newStartHour
            dayStartMinute = newStartMinute
        }
    }

    var dayEndDate: Date {
        get {
            Calendar.current.date(bySettingHour: dayEndHour, minute: dayEndMinute, second: 0, of: Date()) ?? Date()
        }
        set {
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            let newEndHour = components.hour ?? 17
            let newEndMinute = components.minute ?? 0

            // Validate: ensure new end time is after start time
            let newEndMinutes = newEndHour * 60 + newEndMinute
            let currentStartMinutes = dayStartHour * 60 + dayStartMinute

            if newEndMinutes <= currentStartMinutes {
                // Adjust to be at least 1 hour after start time
                let adjustedEndMinutes = currentStartMinutes + 60
                dayEndHour = (adjustedEndMinutes / 60) % 24
                dayEndMinute = adjustedEndMinutes % 60
            } else {
                dayEndHour = newEndHour
                dayEndMinute = newEndMinute
            }
        }
    }

    var workdayDurationMinutes: Int {
        (dayEndHour * 60 + dayEndMinute) - (dayStartHour * 60 + dayStartMinute)
    }

    var isValidWorkDay: Bool {
        let endMinutes = dayEndHour * 60 + dayEndMinute
        let startMinutes = dayStartHour * 60 + dayStartMinute
        return endMinutes > startMinutes
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

        if let data = defaults.data(forKey: Keys.displayStyle),
           let decoded = try? JSONDecoder().decode(DisplayStyle.self, from: data) {
            self.displayStyle = decoded
        } else {
            self.displayStyle = .text
        }

        if let data = defaults.data(forKey: Keys.textDetail),
           let decoded = try? JSONDecoder().decode(TextDetail.self, from: data) {
            self.textDetail = decoded
        } else {
            self.textDetail = .full
        }

        if let data = defaults.data(forKey: Keys.visualDetail),
           let decoded = try? JSONDecoder().decode(VisualDetail.self, from: data) {
            self.visualDetail = decoded
        } else {
            self.visualDetail = .withPercent
        }

        if let data = defaults.data(forKey: Keys.accentColorData),
           let color = Color.fromData(data) {
            self.accentColor = color
        } else {
            self.accentColor = .blue
        }
    }
}

// MARK: - Color Serialization

import SwiftUI

extension Color {
    func toData() -> Data? {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 1

        // Convert to NSColor and try to get RGB components safely
        let nsColor = NSColor(self)

        // Try to convert to sRGB color space for safe component extraction
        if let rgbColor = nsColor.usingColorSpace(.sRGB) {
            rgbColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        } else if let rgbColor = nsColor.usingColorSpace(.deviceRGB) {
            rgbColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        } else {
            // Default to blue if color space conversion fails
            red = 0; green = 0; blue = 1; alpha = 1
        }

        return try? JSONEncoder().encode([red, green, blue, alpha])
    }

    static func fromData(_ data: Data) -> Color? {
        guard let components = try? JSONDecoder().decode([CGFloat].self, from: data),
              components.count == 4 else { return nil }
        return Color(
            red: components[0],
            green: components[1],
            blue: components[2],
            opacity: components[3]
        )
    }

    var nsColor: NSColor {
        NSColor(self)
    }
}
