//
//  OnboardingView.swift
//  clocked-in
//
//  Created by Nimesh on 03/12/2025.
//

import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable private var settings = AppSettings.shared

    private var appIcon: NSImage {
        NSApp.applicationIconImage
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header Section
            VStack(spacing: 12) {
                Image(nsImage: appIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .padding(.top, 32)

                Text("Welcome to Clocked In")
                    .font(.system(size: 24, weight: .bold))

                Text("Track your workday progress from the menu bar")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }

            // Settings Form
            Form {
                Section("Work Day") {
                    DatePicker("Start Time", selection: $settings.dayStartDate, displayedComponents: [.hourAndMinute])
                    DatePicker("End Time", selection: $settings.dayEndDate, displayedComponents: [.hourAndMinute])
                }

                Section("Display Style") {
                    Picker("Style", selection: $settings.displayStyle) {
                        ForEach(DisplayStyle.allCases, id: \.self) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Calculation") {
                    Picker("Week", selection: $settings.weekMode) {
                        ForEach(WeekMode.allCases, id: \.self) { mode in
                            Text(mode.shortTitle).tag(mode)
                        }
                    }

                    Picker("Month & Year", selection: $settings.monthYearMode) {
                        ForEach(CalendarMode.allCases, id: \.self) { mode in
                            Text(mode.shortTitle).tag(mode)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .scrollContentBackground(.hidden)

            // Footer with Get Started Button
            Button(action: completeOnboarding) {
                Text("Get Started")
                    .frame(maxWidth: .infinity)
            }
            .applyGlassProminentButtonStyle()
            .controlSize(.large)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func completeOnboarding() {
        settings.hasCompletedOnboarding = true
        dismiss()
    }
}

// MARK: - Liquid Glass Button Style

extension View {
    @ViewBuilder
    func applyGlassProminentButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Preview
#Preview {
    OnboardingView()
}
