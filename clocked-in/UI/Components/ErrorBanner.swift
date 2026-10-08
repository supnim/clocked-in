import SwiftUI

/// Inline error banner component for displaying errors within views
/// Supports different styles and optional retry functionality
struct ErrorBanner: View {
    let error: AppError
    var onRetry: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil
    var isCompact: Bool = false

    @State private var isVisible = true

    var body: some View {
        if isVisible {
            if isCompact {
                compactBanner
            } else {
                fullBanner
            }
        }
    }

    // MARK: - Compact Banner

    private var compactBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .font(.caption2)
                .foregroundColor(iconColor)

            Text(error.localizedDescription)
                .font(.caption2)
                .foregroundColor(textColor)
                .lineLimit(1)

            Spacer()

            if onRetry != nil {
                Button(action: { onRetry?() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            if onDismiss != nil {
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(backgroundColor)
        .cornerRadius(6)
    }

    // MARK: - Full Banner

    private var fullBanner: some View {
        HStack(spacing: 10) {
            // Icon
            Image(systemName: iconName)
                .font(.subheadline)
                .foregroundColor(iconColor)

            // Message
            VStack(alignment: .leading, spacing: 2) {
                Text(error.localizedDescription)
                    .font(.caption.weight(.medium))
                    .foregroundColor(textColor)

                if let suggestion = error.recoverySuggestion {
                    Text(suggestion)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Actions
            HStack(spacing: 8) {
                if let retry = onRetry, error.isRetryable {
                    Button(action: retry) {
                        Text("Retry")
                            .font(.caption2.weight(.medium))
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                }

                if onDismiss != nil {
                    Button(action: dismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.subheadline)
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(backgroundColor)
        .cornerRadius(8)
    }

    // MARK: - Styling

    private var iconName: String {
        switch error {
        case .network:
            return "wifi.slash"
        case .auth:
            return "lock.fill"
        case .rateLimited:
            return "clock.fill"
        case .serverError:
            return "server.rack"
        case .notFound:
            return "questionmark.circle.fill"
        case .validation:
            return "exclamationmark.triangle.fill"
        default:
            return "exclamationmark.circle.fill"
        }
    }

    private var iconColor: Color {
        switch error {
        case .network:
            return .orange
        case .auth:
            return .red
        case .rateLimited:
            return .yellow
        case .serverError:
            return .red
        default:
            return .red
        }
    }

    private var textColor: Color {
        switch error {
        case .network, .rateLimited:
            return .orange
        default:
            return .red
        }
    }

    private var backgroundColor: Color {
        switch error {
        case .network:
            return .orange.opacity(0.1)
        case .rateLimited:
            return .yellow.opacity(0.1)
        default:
            return .red.opacity(0.1)
        }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.2)) {
            isVisible = false
        }
        onDismiss?()
    }
}

// MARK: - Toast-style Error View

/// A toast notification that appears at the top/bottom of the screen
struct ErrorToast: View {
    let error: AppError
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.headline)
                .foregroundColor(.white)

            Text(error.localizedDescription)
                .font(.footnote.weight(.medium))
                .foregroundColor(.white)
                .lineLimit(2)

            Spacer()

            if onDismiss != nil {
                Button(action: { onDismiss?() }) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.red.opacity(0.9))
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        )
    }
}

// MARK: - Inline Error Text

/// Simple inline error message for forms
struct InlineErrorText: View {
    let message: String
    var isSuccess: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.caption2)

            Text(message)
                .font(.caption2)
        }
        .foregroundColor(isSuccess ? .green : .red)
    }
}

// MARK: - View Extension for Error State

extension View {
    /// Adds an error banner overlay to the view
    @ViewBuilder
    func errorBanner(
        _ error: AppError?,
        onRetry: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) -> some View {
        if let error = error {
            VStack(spacing: 0) {
                ErrorBanner(error: error, onRetry: onRetry, onDismiss: onDismiss)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)

                self
            }
        } else {
            self
        }
    }
}

// MARK: - Preview

#Preview("Error Banners") {
    VStack(spacing: 20) {
        // Full banners
        VStack(alignment: .leading, spacing: 8) {
            Text("Full Banners")
                .font(.caption)
                .foregroundColor(.secondary)

            ErrorBanner(
                error: .network(message: "No internet connection"),
                onRetry: { },
                onDismiss: { }
            )

            ErrorBanner(
                error: .auth(message: "Session expired"),
                onDismiss: { }
            )

            ErrorBanner(
                error: .rateLimited,
                onRetry: { }
            )

            ErrorBanner(
                error: .serverError,
                onRetry: { },
                onDismiss: { }
            )
        }

        Divider()

        // Compact banners
        VStack(alignment: .leading, spacing: 8) {
            Text("Compact Banners")
                .font(.caption)
                .foregroundColor(.secondary)

            ErrorBanner(
                error: .network(message: "Offline"),
                onRetry: { },
                isCompact: true
            )

            ErrorBanner(
                error: .validation(message: "Invalid username"),
                isCompact: true
            )
        }

        Divider()

        // Inline error
        VStack(alignment: .leading, spacing: 8) {
            Text("Inline Messages")
                .font(.caption)
                .foregroundColor(.secondary)

            InlineErrorText(message: "Username already taken")
            InlineErrorText(message: "Friend request sent!", isSuccess: true)
        }

        Divider()

        // Toast
        VStack(alignment: .leading, spacing: 8) {
            Text("Toast")
                .font(.caption)
                .foregroundColor(.secondary)

            ErrorToast(error: .unknown(message: "Something went wrong"), onDismiss: { })
        }
    }
    .padding()
    .frame(width: 320)
    .background(Color.black.opacity(0.8))
}
