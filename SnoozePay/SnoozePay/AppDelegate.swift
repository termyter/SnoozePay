//
//  AppDelegate.swift
//  SnoozePay
//

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
                print("Notification permission denied — alarms may not fire")
                self?.presentNotificationsDisabledAlert()
            }
        }

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
        DispatchQueue.main.async {
            guard
                let windowScene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first,
                let rootVC = windowScene.windows.first?.rootViewController
            else { return }

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

        // Start continuous alarm sound immediately (before presenting the VC)
        let soundID = userInfo["soundID"] as? String ?? "radar"
        AudioService.shared.startAlarmSound(soundID: soundID)

        // Show the alarm firing screen
        presentAlarmFiringScreen(for: userInfo)
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
            presentAlarmFiringScreen(for: userInfo)

        case "SNOOZE_ACTION":
            AudioService.shared.stopAlarmSound()
            handleSnoozeFromNotification(userInfo: userInfo)

        case UNNotificationDismissActionIdentifier:
            // User swiped away notification — stop sound
            AudioService.shared.stopAlarmSound()

        default:
            AudioService.shared.stopAlarmSound()
        }

        completionHandler()
    }

    // MARK: - Helpers

    private func presentAlarmFiringScreen(for userInfo: [AnyHashable: Any]) {
        guard
            let alarmIDString = userInfo["alarmID"] as? String,
            let alarmID = UUID(uuidString: alarmIDString)
        else { return }

        let repo = AlarmRepository()
        guard let alarm = repo.fetch(id: alarmID) else { return }

        DispatchQueue.main.async {
            let firingVC = AlarmFiringViewController(alarm: alarm, snoozeCount: userInfo["snoozeCount"] as? Int ?? 0)
            firingVC.modalPresentationStyle = .fullScreen

            // Find the topmost presented view controller to avoid "already presenting" issues
            guard
                let windowScene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first,
                let rootVC = windowScene.windows.first?.rootViewController
            else { return }

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

    private func handleSnoozeFromNotification(userInfo: [AnyHashable: Any]) {
        guard
            let alarmIDString = userInfo["alarmID"] as? String,
            let alarmID = UUID(uuidString: alarmIDString),
            let snoozeCount = userInfo["snoozeCount"] as? Int
        else { return }

        let repo = AlarmRepository()
        guard let alarm = repo.fetch(id: alarmID) else { return }

        let penalty = alarm.penalty(forSnoozeCount: snoozeCount + 1)

        let charged = BalanceService.shared.charge(amount: penalty, alarmID: alarmID)
        if charged {
            AlarmScheduler.shared.scheduleSnooze(for: alarm, snoozeCount: snoozeCount + 1)
        }
    }
}
