import SwiftUI

/// Sheet for reporting a user to the moderators. Reason must be 1...500 characters.
struct ReportUserView: View {
    let userId: String
    let username: String
    var onReported: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @State private var isSubmitting = false
    @State private var error: AppError?

    static let maxLength = 500

    private var trimmedReason: String {
        reason.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !isSubmitting && !trimmedReason.isEmpty && trimmedReason.count <= Self.maxLength
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Report @\(username)")
                .font(.headline)

            Text("Tell us what happened. Reports are reviewed by the Clocked-In team. If you also want to stop all contact, block this user.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $reason)
                .font(.body)
                .frame(minHeight: 100)
                .padding(4)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(6)
                .accessibilityLabel("Reason for report")
                .onChange(of: reason) { _, newValue in
                    if newValue.count > Self.maxLength {
                        reason = String(newValue.prefix(Self.maxLength))
                    }
                }

            HStack {
                Text("\(trimmedReason.count)/\(Self.maxLength)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
            }

            if let error {
                ErrorBanner(
                    error: error,
                    onDismiss: { self.error = nil },
                    isCompact: true
                )
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(action: submit) {
                    if isSubmitting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Send Report")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit)
            }
        }
        .padding()
        .frame(width: 320)
    }

    private func submit() {
        guard canSubmit else { return }
        let text = trimmedReason
        isSubmitting = true
        error = nil

        Task {
            do {
                try await FriendService.shared.reportUser(userId, reason: text)
                isSubmitting = false
                onReported()
                dismiss()
            } catch let err {
                isSubmitting = false
                error = AppError.from(err)
                ErrorHandler.shared.handle(err, context: "reportUser", showToUser: false)
            }
        }
    }
}
