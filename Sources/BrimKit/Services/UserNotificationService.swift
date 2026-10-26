import Foundation
import UserNotifications

/// Thin wrapper around `UNUserNotificationCenter`. The delegate is set in `init`, so a notification
/// click can open the session's project even when Brim was launched by the notification.
@MainActor
public final class UserNotificationService: NSObject, AgentNotifying, UNUserNotificationCenterDelegate {
    public private(set) var authorization: NotificationAuthorization = .notDetermined
    public var onOpenProject: ((String) -> Void)?

    private let center = UNUserNotificationCenter.current()

    public override init() {
        super.init()
        center.delegate = self
    }

    public func refreshAuthorization() async {
        let settings = await center.notificationSettings()
        authorization = Self.map(settings.authorizationStatus)
        Log.agent.debug("Notification authorization is \(self.authorization.rawValue, privacy: .public)")
    }

    public func requestAuthorization() async -> NotificationAuthorization {
        Log.agent.info("Requesting notification authorization")
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            Log.agent.error("Notification permission request failed: \(error.localizedDescription)")
        }
        await refreshAuthorization()
        Log.agent.info("Notification authorization is \(self.authorization.rawValue, privacy: .public)")
        return authorization
    }

    public func post(_ notification: AgentNotification) {
        guard authorization.isAuthorized else {
            Log.agent.debug("Skipped agent notification; authorization is \(self.authorization.rawValue, privacy: .public)")
            return
        }
        Log.agent.debug("Posting agent notification: \(notification.title, privacy: .public)")

        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        if let cwd = notification.cwd, !cwd.isEmpty {
            content.userInfo = ["cwd": cwd]
        }

        let request = UNNotificationRequest(
            identifier: "brim-agent-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request) { error in
            if let error {
                Log.agent.error("Could not post agent notification: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // The agent module suppresses notifications while a panel is open, so a banner here is useful
        // even when Brim happens to be the active app.
        completionHandler([.banner, .sound])
    }

    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let cwd = response.notification.request.content.userInfo["cwd"] as? String
        if let cwd, !cwd.isEmpty {
            Task { @MainActor [weak self] in
                self?.onOpenProject?(cwd)
            }
        }
        completionHandler()
    }

    private static func map(_ status: UNAuthorizationStatus) -> NotificationAuthorization {
        switch status {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized, .provisional: .authorized
        @unknown default: .notDetermined
        }
    }
}
