import Foundation
import UserNotifications
import AppKit

/// Cross-edition notification utility (first Swift-native shared notification code
/// in the Genesis ecosystem; `whisper_watch.py` + `push_notify.py` use osascript
/// for shell contexts — this is the macOS-app counterpart).
///
/// Strategy:
///   - Try `UNUserNotificationCenter` (modern macOS notification banner)
///   - Always play `NSSound("Glass")` as immediate audible feedback
///     — Glass is the same sound `whisper_watch.py` uses, so the cue is
///       cross-tool consistent inside the operator's environment.
///   - If notification permission is denied or unavailable, sound alone is
///     enough signal that the long-running task has finished.
public actor Notifier {
    public static let shared = Notifier()

    private var authorizationRequested = false
    private var authorizationGranted = false

    private init() {}

    /// Request notification authorization once per app launch. Safe to call multiple times.
    public func requestAuthorizationIfNeeded() async {
        guard !authorizationRequested else { return }
        authorizationRequested = true

        // UNUserNotificationCenter crashes with an uncaught NSException
        // ("bundleProxyForCurrentProcess is nil") when invoked from a bare
        // executable without a real `.app` bundle (e.g. `swift run`, dev-run.sh).
        // Skip authorization entirely in that case — sound feedback still works.
        guard Bundle.main.bundleIdentifier != nil else {
            authorizationGranted = false
            return
        }

        do {
            authorizationGranted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            // Sandboxing or signing issues can make this throw; sound alone still works.
            authorizationGranted = false
        }
    }

    /// Post a notification banner + audible cue.
    /// - Parameters:
    ///   - title: Banner title (e.g. "Genesis Imaging").
    ///   - body: Banner body (e.g. "photo-1024.jpg → 4× upscaled in 2.6 s").
    ///   - sound: Play "Glass" system sound. Default `true`.
    public func notify(title: String, body: String, sound: Bool = true) async {
        if sound {
            // Sound first — runs even if banner is suppressed (foreground app, DND, etc.)
            await MainActor.run {
                _ = NSSound(named: NSSound.Name("Glass"))?.play()
            }
        }

        guard authorizationGranted else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if sound {
            content.sound = .default
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil  // deliver immediately
        )

        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Sound-only feedback (no banner). Useful for non-completion cues.
    public func chime() async {
        await MainActor.run {
            _ = NSSound(named: NSSound.Name("Glass"))?.play()
        }
    }

    /// Lower-pitched error sound (Funk) for failure cues.
    public func errorChime() async {
        await MainActor.run {
            _ = NSSound(named: NSSound.Name("Funk"))?.play()
        }
    }
}
