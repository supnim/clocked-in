import AppKit
import AVFoundation
import UserNotifications

@MainActor
final class NudgeEffects {
    static let shared = NudgeEffects()

    private var audioPlayer: AVAudioPlayer?

    private init() {
        // Request notification permission on init
        Task {
            await requestNotificationPermission()
        }
    }

    // MARK: - Public API

    /// Play nudge effects based on user preferences
    func playNudge(from username: String) {
        let settings = AppSettings.shared

        if settings.nudgeShake {
            shakeScreen()
        }

        if settings.nudgeSound {
            playSound()
        }

        if settings.nudgeNotification {
            showNotification(from: username)
        }
    }

    // MARK: - Screen Shake

    private func shakeScreen() {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.level.rawValue > NSWindow.Level.normal.rawValue }) else {
            // Fall back to shaking all windows
            shakeAllWindows()
            return
        }
        shakeWindow(window)
    }

    private func shakeWindow(_ window: NSWindow) {
        let originalFrame = window.frame
        let shakeDuration: Double = 0.4
        let shakeCount = 6
        let shakeIntensity: CGFloat = 8

        Task {
            for i in 0..<shakeCount {
                let direction: CGFloat = i % 2 == 0 ? 1 : -1
                let decay = CGFloat(shakeCount - i) / CGFloat(shakeCount)
                let offset = shakeIntensity * direction * decay

                await MainActor.run {
                    var newFrame = originalFrame
                    newFrame.origin.x += offset
                    window.setFrame(newFrame, display: false)
                }

                try? await Task.sleep(for: .seconds(shakeDuration / Double(shakeCount)))
            }

            // Reset to original position
            await MainActor.run {
                window.setFrame(originalFrame, display: false)
            }
        }
    }

    private func shakeAllWindows() {
        for window in NSApp.windows where window.isVisible {
            shakeWindow(window)
        }
    }

    // MARK: - Sound

    private func playSound() {
        // Try custom nudge sound first, fall back to system sound
        if let customSoundURL = Bundle.main.url(forResource: "nudge", withExtension: "aiff") {
            playCustomSound(url: customSoundURL)
        } else {
            // Use a fun system sound - "Funk" is playful and attention-grabbing
            NSSound(named: "Funk")?.play()
        }
    }

    private func playCustomSound(url: URL) {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
        } catch {
            // Fall back to system sound
            NSSound(named: "Funk")?.play()
        }
    }

    // MARK: - Notifications

    private func requestNotificationPermission() async {
        let center = UNUserNotificationCenter.current()
        do {
            try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            print("Failed to request notification permission: \(error)")
        }
    }

    private func showNotification(from username: String) {
        let content = UNMutableNotificationContent()
        content.title = "Nudge!"
        content.body = "\(username) nudged you"
        content.sound = .default
        content.categoryIdentifier = "NUDGE"

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to show nudge notification: \(error)")
            }
        }
    }
}
