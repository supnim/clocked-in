import SwiftUI

struct StatusPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable private var authManager = AuthManager.shared

    @State private var customText = ""
    @State private var isUpdating = false
    @FocusState private var isCustomFieldFocused: Bool

    // Preset statuses with icons
    private let presetStatuses: [(icon: String, text: String)] = [
        ("brain.head.profile", "Focusing"),
        ("video.fill", "In a meeting"),
        ("moon.fill", "AFK"),
        ("bell.slash.fill", "Do not disturb"),
        ("cup.and.saucer.fill", "Taking a break")
    ]

    private var currentStatus: String? {
        authManager.currentUser?.statusMessage
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Set Status")
                    .font(.system(size: 16, weight: .semibold))

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(spacing: 12) {
                    // Clear status option (if status exists)
                    if currentStatus != nil {
                        Button(action: clearStatus) {
                            HStack(spacing: 12) {
                                Image(systemName: "xmark.circle")
                                    .font(.system(size: 16))
                                    .foregroundColor(.red)
                                    .frame(width: 24)

                                Text("Clear status")
                                    .font(.system(size: 14))
                                    .foregroundColor(.red)

                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.red.opacity(0.1))
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isUpdating)
                    }

                    // Preset statuses
                    VStack(spacing: 4) {
                        ForEach(presetStatuses, id: \.text) { preset in
                            statusButton(icon: preset.icon, text: preset.text)
                        }
                    }

                    Divider()
                        .padding(.vertical, 8)

                    // Custom status input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Custom status")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            Image(systemName: "pencil")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)

                            TextField("What are you up to?", text: $customText)
                                .textFieldStyle(.plain)
                                .font(.system(size: 14))
                                .focused($isCustomFieldFocused)
                                .onSubmit {
                                    if !customText.isEmpty {
                                        setStatus(customText)
                                    }
                                }

                            if !customText.isEmpty {
                                Button(action: { setStatus(customText) }) {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(.accentColor)
                                }
                                .buttonStyle(.plain)
                                .disabled(isUpdating)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.primary.opacity(0.05))
                        )

                        Text("Max 50 characters")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
        }
        .frame(width: 280, height: 400)
    }

    @ViewBuilder
    private func statusButton(icon: String, text: String) -> some View {
        let isSelected = currentStatus == text

        Button(action: { setStatus(text) }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .frame(width: 24)

                Text(text)
                    .font(.system(size: 14))
                    .foregroundColor(.primary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
        .disabled(isUpdating)
    }

    private func setStatus(_ status: String) {
        let trimmed = String(status.prefix(50))
        guard !trimmed.isEmpty else { return }

        isUpdating = true

        Task {
            do {
                try await updateStatusOnServer(trimmed)
                await MainActor.run {
                    authManager.currentUser?.statusMessage = trimmed
                    isUpdating = false
                    dismiss()
                }
            } catch {
                print("Failed to update status: \(error)")
                await MainActor.run {
                    isUpdating = false
                }
            }
        }
    }

    private func clearStatus() {
        isUpdating = true

        Task {
            do {
                try await updateStatusOnServer(nil)
                await MainActor.run {
                    authManager.currentUser?.statusMessage = nil
                    isUpdating = false
                    dismiss()
                }
            } catch {
                print("Failed to clear status: \(error)")
                await MainActor.run {
                    isUpdating = false
                }
            }
        }
    }

    private func updateStatusOnServer(_ status: String?) async throws {
        struct StatusUpdate: Encodable {
            let statusMessage: String?

            enum CodingKeys: String, CodingKey {
                case statusMessage = "status_message"
            }
        }

        let _: User = try await APIClient.shared.patch(
            "/api/users/me",
            body: StatusUpdate(statusMessage: status)
        )
    }
}

#Preview {
    StatusPickerView()
}
