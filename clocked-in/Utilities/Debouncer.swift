import Foundation

actor Debouncer {
    private var task: Task<Void, Never>?

    func debounce(duration: Duration = .seconds(2), action: @escaping @Sendable () async -> Void) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            await action()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
