import SwiftUI

struct SettingsView: View {
    @Bindable private var authManager = AuthManager.shared
    @Bindable private var appSettings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingHiddenApps = false
    @State private var showingStatusPicker = false

    var body: some View {
        ScrollView {
                VStack(spacing: 20) {

                    // Profile section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Profile")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)

                        if let user = authManager.currentUser {
                            HStack(spacing: 12) {
                                // Avatar
                                AvatarView(
                                    avatarURL: user.avatarUrl,
                                    displayName: user.name,
                                    size: 48
                                )

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(user.name)
                                        .font(.system(size: 16, weight: .medium))
                                    Text("@\(user.username)")
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                }

                                Spacer()
                            }
                        }

                        // Custom status
                        Button(action: { showingStatusPicker = true }) {
                            HStack(spacing: 8) {
                                Image(systemName: "text.bubble")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)

                                if let status = authManager.currentUser?.statusMessage {
                                    Text(status)
                                        .font(.system(size: 13))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                } else {
                                    Text("Set a status...")
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.primary.opacity(0.05))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 8)
                    .sheet(isPresented: $showingStatusPicker) {
                        StatusPickerView()
                    }

                    Divider()

                    // Privacy section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Privacy & Sharing")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)

                        Toggle("Invisible Mode", isOn: $appSettings.isInvisible)
                            .font(.system(size: 14))

                        Toggle("Share Window Titles", isOn: $appSettings.shareWindowTitle)
                            .font(.system(size: 14))

                        Toggle("Share Browser URLs", isOn: $appSettings.shareBrowserURL)
                            .font(.system(size: 14))

                        // Hidden apps section
                        Button(action: { showingHiddenApps = true }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text("Hidden Apps")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.primary)

                                        if !appSettings.hiddenApps.isEmpty {
                                            Text("(\(appSettings.hiddenApps.count))")
                                                .font(.system(size: 12))
                                                .foregroundColor(.secondary)
                                        }
                                    }

                                    Text("Apps you don't want to share activity from")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .sheet(isPresented: $showingHiddenApps) {
                        HiddenAppsManagerView()
                            .frame(minWidth: 300, minHeight: 350)
                    }

                    Divider()

                    // Nudge section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 6) {
                            Image(systemName: "hand.wave.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.orange)
                            Text("Nudges")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.secondary)
                        }

                        Toggle(isOn: $appSettings.nudgeShake) {
                            HStack(spacing: 6) {
                                Image(systemName: "waveform")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                Text("Shake Screen")
                            }
                        }
                        .font(.system(size: 14))

                        Toggle(isOn: $appSettings.nudgeSound) {
                            HStack(spacing: 6) {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                Text("Play Sound")
                            }
                        }
                        .font(.system(size: 14))

                        Toggle(isOn: $appSettings.nudgeNotification) {
                            HStack(spacing: 6) {
                                Image(systemName: "bell.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                Text("Show Notification")
                            }
                        }
                        .font(.system(size: 14))
                    }

                    Divider()

                    // General section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("General")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)

                        Toggle("Launch at Login", isOn: $appSettings.launchAtLogin)
                            .font(.system(size: 14))
                    }

                    Divider()

                    // Account section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Account")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)

                        Button(action: signOut) {
                            Text("Sign Out")
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
        }
    }

    private func signOut() {
        authManager.signOut()
        dismiss()
        // Note: App should handle navigation back to onboarding
    }
}
