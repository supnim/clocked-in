//
//  PercentageCalculator.swift
//  clocked-in
//
//  Created by Nimesh on 03/12/2025.
//

import Foundation

struct PercentageCalculator: @unchecked Sendable {
    let settings: AppSettings
    let calendar = Calendar.current

    // MARK: - Cache

    /// Cache for working days calculations to avoid repeated iterations
    private final class WorkingDaysCache: @unchecked Sendable {
        private var monthKey: String = ""
        private var yearKey: String = ""
        private var monthTotal: Int = 0
        private var yearTotal: Int = 0
        private var monthUntilDay: [Int: Int] = [:]
        private var yearUntilDay: [Int: Int] = [:]

        func getMonthTotal(for key: String) -> Int? {
            guard key == monthKey else { return nil }
            return monthTotal
        }

        func setMonthTotal(_ value: Int, for key: String) {
            if key != monthKey {
                monthKey = key
                monthUntilDay.removeAll()
            }
            monthTotal = value
        }

        func getYearTotal(for key: String) -> Int? {
            guard key == yearKey else { return nil }
            return yearTotal
        }

        func setYearTotal(_ value: Int, for key: String) {
            if key != yearKey {
                yearKey = key
                yearUntilDay.removeAll()
            }
            yearTotal = value
        }

        func getMonthUntil(_ day: Int, for key: String) -> Int? {
            guard key == monthKey else { return nil }
            return monthUntilDay[day]
        }

        func setMonthUntil(_ value: Int, day: Int, for key: String) {
            if key != monthKey {
                monthKey = key
                monthUntilDay.removeAll()
            }
            monthUntilDay[day] = value
        }

        func getYearUntil(_ dayOfYear: Int, for key: String) -> Int? {
            guard key == yearKey else { return nil }
            return yearUntilDay[dayOfYear]
        }

        func setYearUntil(_ value: Int, dayOfYear: Int, for key: String) {
            if key != yearKey {
                yearKey = key
                yearUntilDay.removeAll()
            }
            yearUntilDay[dayOfYear] = value
        }
    }

    private static let cache = WorkingDaysCache()

    init(settings: AppSettings = .shared) {
        self.settings = settings
    }

    // MARK: - Weekday Constants

    private enum Weekday {
        static let sunday = 1
        static let saturday = 7

        static func isWeekend(_ weekday: Int) -> Bool {
            weekday == sunday || weekday == saturday
        }
    }

    // MARK: - Day Calculation

    enum DayStatus {
        case beforeWork
        case working(percentage: Int)
        case overtime
    }

    func calculateDayStatus(at date: Date = Date()) -> DayStatus {
        let now = calendar.dateComponents([.hour, .minute], from: date)
        let currentMinutes = (now.hour ?? 0) * 60 + (now.minute ?? 0)

        let startMinutes = settings.dayStartHour * 60 + settings.dayStartMinute
        let endMinutes = settings.dayEndHour * 60 + settings.dayEndMinute

        if currentMinutes < startMinutes {
            return .beforeWork
        } else if currentMinutes >= endMinutes {
            return .overtime
        } else {
            let elapsed = currentMinutes - startMinutes
            let total = endMinutes - startMinutes
            let percentage = (elapsed * 100) / total
            return .working(percentage: percentage)
        }
    }

    // MARK: - Week Calculation

    func calculateWeekPercentage(at date: Date = Date()) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        // Convert to Monday = 1, Sunday = 7
        let mondayBasedWeekday = weekday == 1 ? 7 : weekday - 1

        let totalDays: Int
        let dayIndex: Int

        switch settings.weekMode {
        case .fullWeek:
            totalDays = 7
            dayIndex = mondayBasedWeekday
        case .workingDays:
            // If weekend, return 100% (week is complete)
            if Weekday.isWeekend(weekday) {
                return 100
            }
            totalDays = 5
            // If weekend, cap at 5
            dayIndex = min(mondayBasedWeekday, 5)
        }

        // Calculate partial day progress
        let dayProgress = calculateDayProgress(at: date)

        // (completedDays + partialDay) / totalDays * 100
        let completedDays = dayIndex - 1
        let percentage = ((Double(completedDays) + dayProgress) / Double(totalDays)) * 100

        return Int(percentage)
    }

    // MARK: - Month Calculation

    func calculateMonthPercentage(at date: Date = Date()) -> Int {
        let dayOfMonth = calendar.component(.day, from: date)
        let range = calendar.range(of: .day, in: .month, for: date)!
        let totalDays: Int
        let dayIndex: Int

        switch settings.monthYearMode {
        case .allDays:
            totalDays = range.count
            dayIndex = dayOfMonth
        case .workingDays:
            totalDays = countWorkingDays(in: date, scope: .month)
            dayIndex = countWorkingDaysUntil(date, scope: .month)
        }

        let weekday = calendar.component(.weekday, from: date)
        let dayProgress = (settings.monthYearMode == .workingDays && Weekday.isWeekend(weekday)) ? 1.0 : calculateDayProgress(at: date)
        let completedDays = dayIndex - 1
        let percentage = ((Double(completedDays) + dayProgress) / Double(totalDays)) * 100

        return min(Int(percentage), 100)
    }

    // MARK: - Year Calculation

    func calculateYearPercentage(at date: Date = Date()) -> Int {
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date)!
        let range = calendar.range(of: .day, in: .year, for: date)!
        let totalDays: Int
        let dayIndex: Int

        switch settings.monthYearMode {
        case .allDays:
            totalDays = range.count
            dayIndex = dayOfYear
        case .workingDays:
            totalDays = countWorkingDays(in: date, scope: .year)
            dayIndex = countWorkingDaysUntil(date, scope: .year)
        }

        let weekday = calendar.component(.weekday, from: date)
        let dayProgress = (settings.monthYearMode == .workingDays && Weekday.isWeekend(weekday)) ? 1.0 : calculateDayProgress(at: date)
        let completedDays = dayIndex - 1
        let percentage = ((Double(completedDays) + dayProgress) / Double(totalDays)) * 100

        return min(Int(percentage), 100)
    }

    // MARK: - Helpers

    private func calculateDayProgress(at date: Date) -> Double {
        switch calculateDayStatus(at: date) {
        case .beforeWork:
            return 0.0
        case .working(let percentage):
            return Double(percentage) / 100.0
        case .overtime:
            return 1.0
        }
    }

    enum Scope {
        case month
        case year
    }

    /// Generate a cache key for month scope (e.g., "2025-12")
    private func monthCacheKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        return "\(components.year!)-\(components.month!)"
    }

    /// Generate a cache key for year scope (e.g., "2025")
    private func yearCacheKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year], from: date)
        return "\(components.year!)"
    }

    func countWorkingDays(in date: Date, scope: Scope) -> Int {
        // Check cache first
        switch scope {
        case .month:
            let key = monthCacheKey(for: date)
            if let cached = Self.cache.getMonthTotal(for: key) {
                return cached
            }
        case .year:
            let key = yearCacheKey(for: date)
            if let cached = Self.cache.getYearTotal(for: key) {
                return cached
            }
        }

        // Cache miss - calculate
        let range: Range<Int>
        let startDate: Date

        switch scope {
        case .month:
            range = calendar.range(of: .day, in: .month, for: date)!
            startDate = calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
        case .year:
            range = calendar.range(of: .day, in: .year, for: date)!
            startDate = calendar.date(from: calendar.dateComponents([.year], from: date))!
        }

        var count = 0
        for dayOffset in 0..<range.count {
            if let day = calendar.date(byAdding: .day, value: dayOffset, to: startDate) {
                let weekday = calendar.component(.weekday, from: day)
                if !Weekday.isWeekend(weekday) {
                    count += 1
                }
            }
        }

        // Store in cache
        switch scope {
        case .month:
            let key = monthCacheKey(for: date)
            Self.cache.setMonthTotal(count, for: key)
        case .year:
            let key = yearCacheKey(for: date)
            Self.cache.setYearTotal(count, for: key)
        }

        return count
    }

    func countWorkingDaysUntil(_ date: Date, scope: Scope) -> Int {
        // Determine day index and check cache
        let dayOfScope: Int
        switch scope {
        case .month:
            dayOfScope = calendar.component(.day, from: date)
            let key = monthCacheKey(for: date)
            if let cached = Self.cache.getMonthUntil(dayOfScope, for: key) {
                return cached
            }
        case .year:
            dayOfScope = calendar.ordinality(of: .day, in: .year, for: date)!
            let key = yearCacheKey(for: date)
            if let cached = Self.cache.getYearUntil(dayOfScope, for: key) {
                return cached
            }
        }

        // Cache miss - calculate
        let startDate: Date
        switch scope {
        case .month:
            startDate = calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
        case .year:
            startDate = calendar.date(from: calendar.dateComponents([.year], from: date))!
        }

        var count = 0
        for dayOffset in 0..<dayOfScope {
            if let day = calendar.date(byAdding: .day, value: dayOffset, to: startDate) {
                let weekday = calendar.component(.weekday, from: day)
                if !Weekday.isWeekend(weekday) {
                    count += 1
                }
            }
        }
        let result = max(count, 1)

        // Store in cache
        switch scope {
        case .month:
            let key = monthCacheKey(for: date)
            Self.cache.setMonthUntil(result, day: dayOfScope, for: key)
        case .year:
            let key = yearCacheKey(for: date)
            Self.cache.setYearUntil(result, dayOfYear: dayOfScope, for: key)
        }

        return result
    }

    // MARK: - Update Interval

    func optimalUpdateInterval() -> TimeInterval {
        // Calculate minutes per 1% change
        let minutesPerPercent = settings.minutesPerPercent
        // Convert to seconds, with a minimum of 30 seconds
        return max(minutesPerPercent * 60, 30)
    }
}
