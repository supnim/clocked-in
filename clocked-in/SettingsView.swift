//
//  SettingsView.swift
//  clocked-in
//
//  Created by Nimesh on 03/12/2025.
//

import SwiftUI

struct SettingsView: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("Work Day") {
                DatePicker("Start Time", selection: $settings.dayStartDate, displayedComponents: [.hourAndMinute])
                DatePicker("End Time", selection: $settings.dayEndDate, displayedComponents: [.hourAndMinute])
            }

            Section("Display") {
                Picker("Week Calculation", selection: $settings.weekMode) {
                    ForEach(WeekMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }

                Picker("Month & Year", selection: $settings.monthYearMode) {
                    ForEach(CalendarMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }

                Picker("Show Unit", selection: $settings.unitDisplayMode) {
                    ForEach(UnitDisplayMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
            }

            Section("General") {
                Toggle("Launch at Login", isOn: Binding(
                    get: { LaunchAtLogin.isEnabled },
                    set: { newValue in
                        try? LaunchAtLogin.setEnabled(newValue)
                        settings.launchAtLogin = newValue
                    }
                ))
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 400, height: 400)
    }
}

#Preview {
    SettingsView()
}
