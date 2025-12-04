//
//  SettingsView.swift
//  clocked-in
//
//  Created by Nimesh on 03/12/2025.
//

import SwiftUI

struct SettingsView: View {
    @Bindable private var settings = AppSettings.shared

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Work Day Section
                SettingsSection(title: "Work Day") {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Start Time")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            DatePicker("", selection: $settings.dayStartDate, displayedComponents: [.hourAndMinute])
                                .labelsHidden()
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("End Time")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            DatePicker("", selection: $settings.dayEndDate, displayedComponents: [.hourAndMinute])
                                .labelsHidden()
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 4)
                }

                // Display Style Section
                SettingsSection(title: "Display Style") {
                    SelectionGrid(selection: $settings.displayStyle) { style in
                        SelectionCard(
                            title: style.rawValue,
                            isSelected: settings.displayStyle == style
                        )
                    }
                }

                // Contextual Detail Section
                if settings.displayStyle == .text {
                    SettingsSection(title: "Text Format") {
                        SelectionGrid(selection: $settings.textDetail, columns: 3) { detail in
                            SelectionCard(
                                title: detail.rawValue,
                                subtitle: detail.example,
                                isSelected: settings.textDetail == detail
                            )
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    SettingsSection(title: "Show Percentage") {
                        SelectionGrid(selection: $settings.visualDetail, columns: 2) { detail in
                            SelectionCard(
                                title: detail.rawValue,
                                isSelected: settings.visualDetail == detail
                            )
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))

                    // Color Picker for visual styles
                    SettingsSection(title: "Accent Color") {
                        HStack {
                            ColorPicker("", selection: $settings.accentColor, supportsOpacity: false)
                                .labelsHidden()

                            Text("Progress indicator color")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Button("Reset") {
                                settings.accentColor = .blue
                            }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 4)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Week Calculation Section
                SettingsSection(title: "Week Calculation") {
                    SelectionGrid(selection: $settings.weekMode, columns: 2) { mode in
                        SelectionCard(
                            title: mode.shortTitle,
                            subtitle: mode.subtitle,
                            isSelected: settings.weekMode == mode
                        )
                    }
                }

                // Month & Year Section
                SettingsSection(title: "Month & Year Calculation") {
                    SelectionGrid(selection: $settings.monthYearMode, columns: 2) { mode in
                        SelectionCard(
                            title: mode.shortTitle,
                            isSelected: settings.monthYearMode == mode
                        )
                    }
                }

                // General Section
                SettingsSection(title: "General") {
                    Toggle("Launch at Login", isOn: Binding(
                        get: { LaunchAtLogin.isEnabled },
                        set: { newValue in
                            try? LaunchAtLogin.setEnabled(newValue)
                            settings.launchAtLogin = newValue
                        }
                    ))
                    .applyGlassToggleStyle()
                    .padding(.horizontal, 4)
                }

                Divider()
                    .padding(.vertical, 8)

                // About Section (footer)
                aboutSection
            }
            .padding(20)
            .animation(.easeInOut(duration: 0.2), value: settings.displayStyle)
        }
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var aboutSection: some View {
        VStack(spacing: 8) {
            Text("Clocked In")
                .font(.headline)

            Text("Version \(appVersion) (\(buildNumber))")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Link("@sup_nim", destination: URL(string: "https://x.com/sup_nim")!)
                Text("•")
                    .foregroundStyle(.tertiary)
                Link("studio.gold", destination: URL(string: "https://studio.gold")!)
            }
            .font(.caption)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
    }
}

// MARK: - Settings Section

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            content
        }
    }
}

// MARK: - Selection Grid

struct SelectionGrid<T: CaseIterable & Hashable, Content: View>: View {
    @Binding var selection: T
    var columns: Int = 4
    @ViewBuilder let content: (T) -> Content

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: min(columns, T.allCases.count))
    }

    var body: some View {
        LazyVGrid(columns: gridColumns, spacing: 8) {
            ForEach(Array(T.allCases), id: \.self) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selection = item
                    }
                } label: {
                    content(item)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Selection Card (Apple-style)

struct SelectionCard: View {
    let title: String
    var subtitle: String? = nil
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .medium))

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
    }

    @ViewBuilder
    private var cardBackground: some View {
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: 10)
                .fill(.quinary)
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        }
    }
}

// MARK: - Model Extensions for Card Display

extension WeekMode {
    var shortTitle: String {
        switch self {
        case .fullWeek: return "Full Week"
        case .workingDays: return "Working Days"
        }
    }

    var subtitle: String {
        switch self {
        case .fullWeek: return "Mon–Sun"
        case .workingDays: return "Mon–Fri"
        }
    }
}

extension CalendarMode {
    var shortTitle: String {
        switch self {
        case .allDays: return "All Days"
        case .workingDays: return "Working Days"
        }
    }
}

// MARK: - Toggle Style

extension View {
    @ViewBuilder
    func applyGlassToggleStyle() -> some View {
        // On macOS 26+, standard toggles automatically adopt Liquid Glass styling
        // We just use .switch style which looks best on all versions
        self.toggleStyle(.switch)
    }
}

#Preview {
    SettingsView()
        .frame(width: 420, height: 680)
}
