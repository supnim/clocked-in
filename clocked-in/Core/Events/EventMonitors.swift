import AppKit
import Combine

@MainActor
class EventMonitors {
    static let shared = EventMonitors()

    let mouseLocation = CurrentValueSubject<CGPoint, Never>(.zero)
    let mouseDown = PassthroughSubject<NSEvent, Never>()

    private var mouseMoveMonitor: EventMonitor?
    private var mouseDownMonitor: EventMonitor?
    private var mouseDraggedMonitor: EventMonitor?

    private var isRunning = false

    private init() {
        start()
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        setupMonitors()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        mouseMoveMonitor?.stop()
        mouseDownMonitor?.stop()
        mouseDraggedMonitor?.stop()
        mouseMoveMonitor = nil
        mouseDownMonitor = nil
        mouseDraggedMonitor = nil
    }

    private func setupMonitors() {
        mouseMoveMonitor = EventMonitor(mask: .mouseMoved) { [weak self] _ in
            Task { @MainActor [weak self] in self?.mouseLocation.send(NSEvent.mouseLocation) }
        }
        mouseMoveMonitor?.start()

        mouseDownMonitor = EventMonitor(mask: .leftMouseDown) { [weak self] event in
            Task { @MainActor [weak self] in self?.mouseDown.send(event) }
        }
        mouseDownMonitor?.start()

        mouseDraggedMonitor = EventMonitor(mask: .leftMouseDragged) { [weak self] _ in
            Task { @MainActor [weak self] in self?.mouseLocation.send(NSEvent.mouseLocation) }
        }
        mouseDraggedMonitor?.start()
    }
}
