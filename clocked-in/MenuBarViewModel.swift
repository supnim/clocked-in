//
//  MenuBarViewModel.swift
//  clocked-in
//
//  Created by Nimesh on 03/12/2025.
//

import Foundation
import SwiftUI

@MainActor
@Observable
final class MenuBarViewModel {
    private let settings: AppSettings
    private let calculator: PercentageCalculator
    private var updateTask: Task<Void, Never>?

    // MARK: - Public Properties

    var displayText: String = ""
    var currentPercentage: Int = 0
    var isOvertime: Bool = false

    var currentMode: ViewMode {
        settings.currentViewMode
    }

    var tooltipText: String {
        generateTooltipText()
    }

    var displayStyle: DisplayStyle {
        settings.displayStyle
    }

    var textDetail: TextDetail {
        settings.textDetail
    }

    var visualDetail: VisualDetail {
        settings.visualDetail
    }

    var accentColor: Color {
        settings.accentColor
    }

    var weekMode: WeekMode {
        settings.weekMode
    }

    var monthYearMode: CalendarMode {
        settings.monthYearMode
    }

    // MARK: - Initialization

    init(settings: AppSettings = .shared) {
        self.settings = settings
        self.calculator = PercentageCalculator(settings: settings)
        // Set initial display text respecting unitDisplayMode
        displayText = formatDisplay(mode: .day, percentage: 0)
        updateDisplay()
    }

    // MARK: - Public Methods

    func cycleMode() {
        settings.currentViewMode = settings.currentViewMode.next()
        updateDisplay()
        restartTimer()
    }

    func updateDisplay() {
        switch currentMode {
        case .day:
            updateDayDisplay()
        case .week:
            updateWeekDisplay()
        case .month:
            updateMonthDisplay()
        case .year:
            updateYearDisplay()
        }
    }

    func startTimer() {
        stopTimer()
        updateTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.updateDisplay()
                let interval = self?.calculator.optimalUpdateInterval() ?? 60
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func stopTimer() {
        updateTask?.cancel()
        updateTask = nil
    }

    // MARK: - Private Methods

    private func updateDayDisplay() {
        let status = calculator.calculateDayStatus()

        switch status {
        case .beforeWork:
            currentPercentage = 0
            isOvertime = false
            displayText = formatDisplay(mode: .day, percentage: 0)
        case .working(let percentage):
            currentPercentage = percentage
            isOvertime = false
            displayText = formatDisplay(mode: .day, percentage: percentage)
        case .overtime:
            currentPercentage = 100
            isOvertime = true
            displayText = "Overtime"
        }
    }

    private func updateWeekDisplay() {
        let percentage = calculator.calculateWeekPercentage()
        currentPercentage = percentage
        isOvertime = false
        displayText = formatDisplay(mode: .week, percentage: percentage)
    }

    private func updateMonthDisplay() {
        let percentage = calculator.calculateMonthPercentage()
        currentPercentage = percentage
        isOvertime = false
        displayText = formatDisplay(mode: .month, percentage: percentage)
    }

    private func updateYearDisplay() {
        let percentage = calculator.calculateYearPercentage()
        currentPercentage = percentage
        isOvertime = false
        displayText = formatDisplay(mode: .year, percentage: percentage)
    }

    private func formatDisplay(mode: ViewMode, percentage: Int) -> String {
        let percentageText = "\(percentage)%"

        // For visual styles, the StatusBarRenderer handles display
        // This is only used for text style
        switch settings.textDetail {
        case .full:
            return "\(mode.rawValue) \(percentageText)"
        case .compact:
            let icon: String
            switch mode {
            case .day: icon = "D"
            case .week: icon = "W"
            case .month: icon = "M"
            case .year: icon = "Y"
            }
            return "\(icon) \(percentageText)"
        case .minimal:
            return percentageText
        }
    }

    private func restartTimer() {
        stopTimer()
        startTimer()
    }

    private func generateTooltipText() -> String {
        switch currentMode {
        case .day:
            return generateDayTooltip()
        case .week:
            return generateWeekTooltip()
        case .month:
            return generateMonthTooltip()
        case .year:
            return generateYearTooltip()
        }
    }

    private func generateDayTooltip() -> String {
        let status = calculator.calculateDayStatus()

        switch status {
        case .beforeWork:
            let startTime = formatTime(hour: settings.dayStartHour, minute: settings.dayStartMinute)
            let endTime = formatTime(hour: settings.dayEndHour, minute: settings.dayEndMinute)
            return "Day: \(startTime) - \(endTime) (0%)"
        case .working(let percentage):
            let startTime = formatTime(hour: settings.dayStartHour, minute: settings.dayStartMinute)
            let endTime = formatTime(hour: settings.dayEndHour, minute: settings.dayEndMinute)
            return "Day: \(startTime) - \(endTime) (\(percentage)%)"
        case .overtime:
            return "Day: Overtime"
        }
    }

    private func generateWeekTooltip() -> String {
        let percentage = calculator.calculateWeekPercentage()
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: Date())
        let mondayBasedWeekday = weekday == 1 ? 7 : weekday - 1

        switch settings.weekMode {
        case .fullWeek:
            let dayIndex = mondayBasedWeekday
            return "Week: Day \(dayIndex) of 7 (\(percentage)%)"
        case .workingDays:
            let dayIndex = min(mondayBasedWeekday, 5)
            return "Week: Day \(dayIndex) of 5 (\(percentage)%)"
        }
    }

    private func generateMonthTooltip() -> String {
        let percentage = calculator.calculateMonthPercentage()
        let calendar = Calendar.current
        let date = Date()
        let dayOfMonth = calendar.component(.day, from: date)
        let monthName = date.formatted(.dateTime.month(.wide))

        switch settings.monthYearMode {
        case .allDays:
            let range = calendar.range(of: .day, in: .month, for: date)!
            let totalDays = range.count
            return "\(monthName): Day \(dayOfMonth) of \(totalDays) (\(percentage)%)"
        case .workingDays:
            let totalWorkingDays = calculator.countWorkingDays(in: date, scope: .month)
            let workingDaysUntil = calculator.countWorkingDaysUntil(date, scope: .month)
            return "\(monthName): Working day \(workingDaysUntil) of \(totalWorkingDays) (\(percentage)%)"
        }
    }

    private func generateYearTooltip() -> String {
        let percentage = calculator.calculateYearPercentage()
        let calendar = Calendar.current
        let date = Date()
        let year = calendar.component(.year, from: date)
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date)!

        switch settings.monthYearMode {
        case .allDays:
            let range = calendar.range(of: .day, in: .year, for: date)!
            let totalDays = range.count
            return "\(year): Day \(dayOfYear) of \(totalDays) (\(percentage)%)"
        case .workingDays:
            let totalWorkingDays = calculator.countWorkingDays(in: date, scope: .year)
            let workingDaysUntil = calculator.countWorkingDaysUntil(date, scope: .year)
            return "\(year): Working day \(workingDaysUntil) of \(totalWorkingDays) (\(percentage)%)"
        }
    }

    private func formatTime(hour: Int, minute: Int) -> String {
        let calendar = Calendar.current
        let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
