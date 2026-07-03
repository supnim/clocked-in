import SwiftUI

enum UsernamePickerState {
    case entering
    case checking
    case available
    case taken
    case error(String)
}

@MainActor
@Observable
class UsernamePickerViewModel {
    var username = ""
    var state: UsernamePickerState = .entering
    var canSubmit = false

    private var debounceTask: Task<Void, Never>?

    func validateAndCheckAvailability() {
        // Cancel previous check
        debounceTask?.cancel()

        // Local validation first
        let validation = UsernameService.shared.validateUsernameDetailed(username)
        if let validationError = validation.error {
            state = .error(validationError.localizedDescription ?? "Invalid username")
            canSubmit = false
            return
        }

        // If valid locally, check availability after debounce
        state = .checking
        canSubmit = false

        debounceTask = Task {
            try? await Task.sleep(for: .seconds(0.5)) // Debounce
            guard !Task.isCancelled else { return }

            do {
                let available = try await UsernameService.shared.checkAvailability(username)
                guard !Task.isCancelled else { return }

                state = available ? .available : .taken
                canSubmit = available
            } catch {
                state = .error("Failed to check availability")
                canSubmit = false
            }
        }
    }

    func submit() async throws {
        guard canSubmit else { return }

        let uid = IdentityService.shared.getOrCreateUserUUID()
        try await UsernameService.shared.claimUsername(username, for: uid)
    }
}

struct UsernamePickerView: View {
    @State private var viewModel = UsernamePickerViewModel()
    @State private var isSubmitting = false
    @FocusState private var isUsernameFocused: Bool

    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            // Title
            Text("Welcome to Clocked-In")
                .font(.title3.weight(.semibold))

            // Description
            Text("See what your friends are working on")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            // Username input
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Text("@")
                        .foregroundColor(.secondary)
                        .font(.body)

                    TextField("", text: $viewModel.username)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .focused($isUsernameFocused)
                        .accessibilityLabel("Username")
                        .accessibilityHint("Enter your desired username")
                        .onChange(of: viewModel.username) { oldValue, newValue in
                            // Force lowercase
                            if newValue != newValue.lowercased() {
                                viewModel.username = newValue.lowercased()
                            }
                            // Limit length
                            if newValue.count > 20 {
                                viewModel.username = String(newValue.prefix(20))
                            }
                            // Trigger validation
                            viewModel.validateAndCheckAvailability()
                        }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )

                // Status message
                HStack(spacing: 4) {
                    switch viewModel.state {
                    case .entering:
                        EmptyView()
                    case .checking:
                        ProgressView()
                            .scaleEffect(0.5)
                        Text("Checking availability...")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    case .available:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption2)
                        Text("✓ Available!")
                            .font(.caption2)
                            .foregroundColor(.green)
                    case .taken:
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                            .font(.caption2)
                        Text("✗ Username is taken")
                            .font(.caption2)
                            .foregroundColor(.red)
                    case .error(let message):
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.caption2)
                        Text(message)
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            }

            // Instructions
            Text("This is how friends will find you.\nYou can change it later in settings.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)

            // Submit button
            Button(action: submitUsername) {
                if isSubmitting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                } else {
                    Text("Get Started")
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(!viewModel.canSubmit || isSubmitting)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(viewModel.canSubmit && !isSubmitting ? Color.accentColor : Color.gray.opacity(0.3))
            .foregroundColor(viewModel.canSubmit && !isSubmitting ? .white : .secondary)
            .cornerRadius(6)
            .keyboardShortcut(.defaultAction)
        }
        .padding(16)
        .frame(width: 280)
        .onAppear { isUsernameFocused = true }
    }

    private func submitUsername() {
        guard viewModel.canSubmit && !isSubmitting else { return }

        isSubmitting = true

        Task {
            do {
                try await viewModel.submit()
                onComplete()
            } catch {
                viewModel.state = .error(error.localizedDescription)
                viewModel.canSubmit = false
                isSubmitting = false
            }
        }
    }
}