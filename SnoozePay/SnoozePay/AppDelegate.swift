//
//  AppDelegate.swift
//  SnoozePay
//

import os
import UIKit
import UserNotifications

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
                AppLogger.notifications.warning("permission denied — alarms may not fire")
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
                AppLogger.notifications.debug("no rootVC yet, deferring notifications-disabled alert")
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
            AppLogger.notifications.error(
                "willPresent: invalid alarm payload \(String(describing: userInfo), privacy: .private)"
            )
            completionHandler([])
            return
        }

        // Start continuous alarm sound immediately (before presenting the VC)
        AudioService.shared.startAlarmSound(soundID: payload.soundID)

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

        switch response.actionIdentifier {
        case "DISMISS_ACTION":
            // Dismiss from notification action — stop sound, no charge
            AudioService.shared.stopAlarmSound()

        case UNNotificationDefaultActionIdentifier:
            // User tapped notification banner — present alarm screen
            // AudioService will be started by AlarmFiringViewController
            if let payload = AlarmNotificationPayload(userInfo: userInfo) {
                presentAlarmFiringScreen(for: payload)
            } else {
                AppLogger.notifications.error(
                    "default action: invalid alarm payload \(String(describing: userInfo), privacy: .private)"
                )
                AudioService.shared.stopAlarmSound()
            }

        case "SNOOZE_ACTION":
            AudioService.shared.stopAlarmSound()
            let outcome = AlarmFiringCoordinator.shared.handleSnooze(userInfo: userInfo)
            switch outcome {
            case .invalidPayload:
                AppLogger.notifications.error("SNOOZE_ACTION: invalid payload, snooze skipped")
            case .alarmNotFound:
                AppLogger.notifications.warning("SNOOZE_ACTION: alarm not found, snooze skipped")
            case .insufficientFunds:
                AppLogger.notifications.notice(
                    "SNOOZE_ACTION: insufficient funds — snooze skipped, alarm will not repeat"
                )
            case let .scheduled(newSnoozeCount, charged):
                AppLogger.notifications.info("SNOOZE_ACTION: snooze #\(newSnoozeCount) scheduled, charged=\(charged)")
            }

        case UNNotificationDismissActionIdentifier:
            // User swiped away notification — stop sound
            AudioService.shared.stopAlarmSound()

        default:
            AudioService.shared.stopAlarmSound()
        }

        completionHandler()
    }

    // MARK: - Helpers

    private func presentAlarmFiringScreen(for payload: AlarmNotificationPayload) {
        guard let alarm = AlarmRepository.shared.fetch(id: payload.alarmID) else {
            // Audio may already be playing from willPresent — stop it so the user
            // is not stuck with a silent-screen + sounding alarm we can't dismiss.
            AppLogger.alarms.warning(
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
                AppLogger.notifications.error("no window scene, stopping audio")
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
