//
//  AppDelegate.swift
//  SnoozePay
//

import UIKit
import CoreData
import UserNotifications

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Warm up Core Data stack
        _ = PersistenceController.shared

        // Register notification categories and request permission
        AlarmScheduler.shared.registerCategories()
        AlarmScheduler.shared.requestPermission { granted in
            if !granted {
                print("Notification permission denied — alarms may not fire")
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
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {

    // Called when app is in foreground and notification arrives
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show the alarm firing screen
        presentAlarmFiringScreen(for: notification.request.content.userInfo)
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
        case "DISMISS_ACTION", UNNotificationDefaultActionIdentifier:
            // Just dismiss — no charge
            break

        case "SNOOZE_ACTION":
            handleSnoozeFromNotification(userInfo: userInfo)

        default:
            break
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
            firingVC.modalPresentationStyle = .overFullScreen
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first?.windows.first?.rootViewController?.present(firingVC, animated: false)
        }
    }

    private func handleSnoozeFromNotification(userInfo: [AnyHashable: Any]) {
        guard
            let alarmIDString = userInfo["alarmID"] as? String,
            let alarmID = UUID(uuidString: alarmIDString),
            let penaltyAmount = userInfo["penaltyAmount"] as? Double,
            let snoozeCount = userInfo["snoozeCount"] as? Int,
            let snoozeMinutes = userInfo["snoozeMinutes"] as? Int
        else { return }

        let progressiveScale = userInfo["progressiveScale"] as? Bool ?? false

        // Calculate penalty for this snooze
        let penalty: Double
        if progressiveScale && snoozeCount > 0 {
            penalty = penaltyAmount * pow(2.0, Double(snoozeCount))
        } else {
            penalty = penaltyAmount
        }

        // Attempt to charge
        let charged = BalanceService.shared.charge(amount: penalty, alarmID: alarmID)
        if charged {
            // Reschedule snooze
            let repo = AlarmRepository()
            if let alarm = repo.fetch(id: alarmID) {
                AlarmScheduler.shared.scheduleSnooze(for: alarm, snoozeCount: snoozeCount + 1)
            }
        }
    }
}
