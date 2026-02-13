import SwiftUI

enum UsernamePickerState {
    case entering
    case checking
    case available
    case taken
    case error(String)
}

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

                await MainActor.run {
                    state = available ? .available : .taken
                    canSubmit = available
                }
            } catch {
                await MainActor.run {
                    state = .error("Failed to check availability")
                    canSubmit = false
                }
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

    let onComplete: () -> Void

    // Inject notch view model for completion handling
    var notchViewModel: NotchViewModel?

    var body: some View {
        VStack(spacing: 16) {
            // Title
            Text("Welcome to Clocked-In")
                .font(.system(size: 18, weight: .semibold))

            // Description
            Text("See what your friends are working on")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            // Username input
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Text("@")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))

                    TextField("", text: $viewModel.username)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
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
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    case .available:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 11))
                        Text("✓ Available!")
                            .font(.system(size: 11))
                            .foregroundColor(.green)
                    case .taken:
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                            .font(.system(size: 11))
                        Text("✗ Username is taken")
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                    case .error(let message):
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 11))
                        Text(message)
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                    }
                }
            }

            // Instructions
            Text("This is how friends will find you.\nYou can change it later in settings.")
                .font(.system(size: 10))
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
                        .font(.system(size: 14, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(!viewModel.canSubmit || isSubmitting)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(viewModel.canSubmit && !isSubmitting ? Color.blue : Color.gray.opacity(0.3))
            .foregroundColor(viewModel.canSubmit && !isSubmitting ? .white : .secondary)
            .cornerRadius(6)
        }
        .padding(16)
        .frame(width: 280)
    }

    private func submitUsername() {
        guard viewModel.canSubmit && !isSubmitting else { return }

        isSubmitting = true

        Task {
            do {
                try await viewModel.submit()
                await MainActor.run {
                    onComplete()
                    notchViewModel?.onUsernameSetupComplete()
                }
            } catch {
                await MainActor.run {
                    viewModel.state = .error(error.localizedDescription)
                    viewModel.canSubmit = false
                    isSubmitting = false
                }
            }
        }
    }
}