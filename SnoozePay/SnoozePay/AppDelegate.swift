//
//  AppDelegate.swift
//  SnoozePay
//

import UIKit
import UserNotifications
import os

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Register notification categories and request permission
        AlarmScheduler.shared.registerCategories()
        AlarmScheduler.shared.requestPermission { [weak self] granted in
            if !granted {
                AppLogger.appDelegate.notice("notification permission denied — alarms may not fire")
                self?.presentNotificationsDisabledAlert()
            }
        }

        // Eagerly construct StoreKitService so its Transaction.updates listener
        // starts at app launch — otherwise deferred Ask-to-Buy approvals / refunds
        // pile up unprocessed until the user opens TopUp.
        _ = StoreKitService.shared

        // Handle notification responses
        UNUserNotificationCenter.current().delegate = self

        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(
        _ application: UIApplication,
        didDiscardSceneSessions sceneSessions: Set<UISceneSession>
    ) {}

    // MARK: - Permission UI

    private func presentNotificationsDisabledAlert() {
        DispatchQueue.main.async { [weak self] in
            // Cold-start: permission callback may fire before SceneDelegate attaches
            // the window. Defer until a scene becomes active rather than dropping silently.
            guard
                let windowScene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first,
                let rootVC = windowScene.windows.first?.rootViewController
            else {
                AppLogger.appDelegate.info("no rootVC yet, deferring notifications-disabled alert")
                self?.deferNotificationsDisabledAlertUntilSceneActive()
                return
            }

            self?.showNotificationsDisabledAlert(on: rootVC)
        }
    }

    private func deferNotificationsDisabledAlertUntilSceneActive() {
        var observer: NSObjectProtocol?
        observer = NotificationCenter.default.addObserver(
            forName: UIScene.didActivateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            if let observer = observer {
                NotificationCenter.default.removeObserver(observer)
            }
            self?.presentNotificationsDisabledAlert()
        }
    }

    private func showNotificationsDisabledAlert(on rootVC: UIViewController) {
        let alert = UIAlertController(
            title: "Уведомления выключены",
            message: "Без разрешения на уведомления будильники не сработают. Включите их в Настройках.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Настройки", style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        })

        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        topVC.present(alert, animated: true)
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {

    // Called when app is in foreground and notification arrives
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo

        guard let payload = AlarmNotificationPayload(userInfo: userInfo) else {
            // Malformed payload — surface and bail rather than playing audio we
            // can never stop because the firing screen will never be presented.
            AppLogger.appDelegate.error(
                "willPresent: invalid alarm payload \(userInfo, privacy: .private(mask: .hash))"
            )
            completionHandler([])
            return
        }

        // Start continuous alarm sound immediately (before presenting the VC).
        // Passing `alarmID` lets AudioService track ownership so a stacking
        // race between firing VCs cannot silence the wrong alarm (#116).
        AudioService.shared.startAlarmSound(
            soundID: payload.soundID,
            alarmID: payload.alarmID
        )

        // Show the alarm firing screen
        presentAlarmFiringScreen(for: payload)
        completionHandler([])
    }

    // Called when user taps a notification action
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        let payload = AlarmNotificationPayload(userInfo: userInfo)
        switch response.actionIdentifier {
        case "DISMISS_ACTION":
            // Dismiss from notification action — stop sound, no charge.
            // Gate on ownership so a notification action targeting alarm A
            // cannot silence audio that has already been claimed by alarm B
            // (stacking-race symmetry with #116).
            stopAlarmSoundIfOwner(of: payload, action: "DISMISS_ACTION")

        case UNNotificationDefaultActionIdentifier:
            // User tapped notification banner — present alarm screen
            // AudioService will be started by AlarmFiringViewController
            if let payload {
                presentAlarmFiringScreen(for: payload)
            } else {
                AppLogger.appDelegate.error(
                    "default action: invalid alarm payload \(userInfo, privacy: .private(mask: .hash))"
                )
                AudioService.shared.stopAlarmSound()
            }

        case "SNOOZE_ACTION":
            stopAlarmSoundIfOwner(of: payload, action: "SNOOZE_ACTION")
            let outcome = AlarmFiringCoordinator.shared.handleSnooze(userInfo: userInfo)
            switch outcome {
            case .invalidPayload:
                AppLogger.appDelegate.error("SNOOZE_ACTION: invalid payload, snooze skipped")
            case .alarmNotFound:
                AppLogger.appDelegate.notice("SNOOZE_ACTION: alarm not found, snooze skipped")
            case .insufficientFunds:
                AppLogger.appDelegate.notice(
                    "SNOOZE_ACTION: insufficient funds — snooze skipped, alarm will not repeat"
                )
            case let .scheduled(newSnoozeCount, charged):
                AppLogger.appDelegate.info(
                    "SNOOZE_ACTION: snooze #\(newSnoozeCount, privacy: .public) scheduled, charged=\(charged, privacy: .public)"
                )
            }

        case UNNotificationDismissActionIdentifier:
            // User swiped away notification — stop sound. Gate on ownership
            // for the same reason as DISMISS_ACTION above.
            stopAlarmSoundIfOwner(of: payload, action: "swipe-dismiss")

        default:
            AppLogger.appDelegate.notice(
                "unknown notification action \(response.actionIdentifier, privacy: .public) — stopping audio unconditionally"
            )
            AudioService.shared.stopAlarmSound()
        }

        completionHandler()
    }

    /// Stop the alarm sound only if its session is currently owned by the
    /// alarm referenced in `payload`. Used to defend against the stacking
    /// race where a notification action for alarm A arrives after alarm B
    /// has already claimed the audio pipeline (#116). When the payload is
    /// `nil` (un-parseable) we fall back to unconditional stop and log so
    /// the caller can audit. Always logs the decision either way.
    private func stopAlarmSoundIfOwner(
        of payload: AlarmNotificationPayload?,
        action: String
    ) {
        guard let payload else {
            AppLogger.appDelegate.error(
                "\(action, privacy: .public): missing payload — stopping audio unconditionally"
            )
            AudioService.shared.stopAlarmSound()
            return
        }
        let owner = AudioService.shared.currentAlarmID
        guard owner == payload.alarmID else {
            AppLogger.appDelegate.notice(
                "\(action, privacy: .public): skipping stop — audio session owned by \(String(describing: owner), privacy: .private), payload alarm=\(payload.alarmID, privacy: .private)"
            )
            return
        }
        AudioService.shared.stopAlarmSound()
    }

    // MARK: - Helpers

    private func presentAlarmFiringScreen(for payload: AlarmNotificationPayload) {
        let alarm: Alarm?
        do {
            // Use the checked variant so a corrupt UserDefaults blob surfaces
            // a logged decode error instead of being indistinguishable from
            // "alarm doesn't exist" — without this we silently bail on a
            // recoverable glitch and the user wonders why the alarm fired
            // but never showed a screen (issue #117).
            alarm = try AlarmRepository.shared.fetchChecked(id: payload.alarmID)
        } catch {
            let errorDesc = String(describing: error)
            AppLogger.appDelegate.error(
                "alarm fetch failed for \(payload.alarmID, privacy: .private): \(errorDesc, privacy: .public)"
            )
            AudioService.shared.stopAlarmSound()
            return
        }
        guard let alarm else {
            // Audio may already be playing from willPresent — stop it so the user
            // is not stuck with a silent-screen + sounding alarm we can't dismiss.
            AppLogger.appDelegate.error(
                "alarm not found (repo returned nil for \(payload.alarmID, privacy: .private)), stopping audio"
            )
            AudioService.shared.stopAlarmSound()
            return
        }

        DispatchQueue.main.async {
            let firingVC = AlarmFiringViewController(alarm: alarm, snoozeCount: payload.snoozeCount)
            firingVC.modalPresentationStyle = .fullScreen

            // Find the topmost presented view controller to avoid "already presenting" issues
            guard
                let windowScene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first,
                let rootVC = windowScene.windows.first?.rootViewController
            else {
                AppLogger.appDelegate.error("no window scene, stopping audio")
                AudioService.shared.stopAlarmSound()
                return
            }

            var topVC = rootVC
            while let presented = topVC.presentedViewController {
                // If an alarm firing screen is already showing, dismiss it first
                if presented is AlarmFiringViewController {
                    presented.dismiss(animated: false) {
                        topVC.present(firingVC, animated: false)
                    }
                    return
                }
                topVC = presented
            }

            topVC.present(firingVC, animated: false)
        }
    }

}
