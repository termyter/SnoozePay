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
            // `handleSnooze` is async — we must keep the system
            // `completionHandler` alive until it resolves, otherwise iOS may
            // suspend the app before the scheduler callback fires (#130).
            //
            // BUT: if the scheduler chain hangs (UN daemon unresponsive, main
            // queue starved) the closure never fires and iOS terminates the
            // process at ~30s, silently dropping the snooze and the fallback
            // banner. A 25s watchdog calls `completionHandler` once whichever
            // path resolves first wins — preventing the timeout class of
            // silent failure (silent-failure-hunter CRITICAL on #132).
            let resolveLock = NSLock()
            var didResolve = false
            let resolveOnce: () -> Void = {
                resolveLock.lock()
                defer { resolveLock.unlock() }
                guard !didResolve else { return }
                didResolve = true
                completionHandler()
            }
            let watchdog = DispatchWorkItem {
                AppLogger.appDelegate.fault(
                    "SNOOZE_ACTION watchdog fired — coordinator did not resolve in 25s, releasing completionHandler"
                )
                resolveOnce()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 25, execute: watchdog)
            AlarmFiringCoordinator.shared.handleSnooze(userInfo: userInfo) { [weak self] outcome in
                watchdog.cancel()
                self?.logSnoozeOutcome(outcome)
                switch outcome {
                case let .scheduleFailed(error):
                    self?.postSnoozeScheduleFailedBanner(error: error, refundLanded: true)
                case let .scheduleFailedAndRefundFailed(error):
                    self?.postSnoozeScheduleFailedBanner(error: error, refundLanded: false)
                default:
                    break
                }
                resolveOnce()
            }
            return // async path + watchdog own `completionHandler` from here on

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
            // Surface the decode failure to the user — without this they hear
            // the alarm cut off and get no firing screen with no diagnostic.
            // The alert is presented from the same dispatch we'd use for the
            // firing screen so it reaches whichever VC is on top.
            presentAlarmDataCorruptedAlert(error: error)
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

    /// Centralised logging for every `SnoozeOutcome` branch — extracted from
    /// the `didReceive` switch so that path stays under cyclomatic-complexity
    /// limits and the logging vocabulary lives next to the fallback-banner
    /// helper that depends on the same outcome.
    private func logSnoozeOutcome(_ outcome: AlarmFiringCoordinator.SnoozeOutcome) {
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
                "SNOOZE_ACTION: scheduled #\(newSnoozeCount, privacy: .public) charged=\(charged, privacy: .public)"
            )
        case let .scheduleFailed(error):
            // Penalty was refunded inside the coordinator. We log the cause
            // here and rely on the caller to post the user-facing banner.
            let desc = error.localizedDescription
            AppLogger.appDelegate.error(
                "SNOOZE_ACTION: schedule failed (\(desc, privacy: .public)) — posting fallback banner (refunded)"
            )
        case let .scheduleFailedAndRefundFailed(error):
            // Both schedule AND refund failed — money was taken, alarm won't
            // re-fire, refund didn't land. Stronger banner copy is posted by
            // the caller; we log at fault-level for forensics.
            let desc = error.localizedDescription
            AppLogger.appDelegate.fault(
                "SNOOZE_ACTION: schedule AND refund failed (\(desc, privacy: .public)) — wallet desync"
            )
        }
    }

    /// Schedule a local notification that surfaces immediately when the
    /// snooze action's reschedule attempt failed. The user is no longer in
    /// the app (notification actions run from the lock screen / banner), so
    /// a UIAlertController would never reach them — only a banner the system
    /// itself delivers will. The penalty has already been refunded by the
    /// coordinator before this is called (issue #130).
    private func postSnoozeScheduleFailedBanner(
        error: AlarmScheduler.SchedulingError,
        refundLanded: Bool
    ) {
        let detail = error.errorDescription ?? error.localizedDescription
        let content = UNMutableNotificationContent()
        content.title = "Снуз не запланирован"
        if refundLanded {
            content.body = "Установите запасной — \(detail)"
        } else {
            // Penalty was charged but refund failed — surface this so the user
            // knows to reach out instead of silently absorbing the loss.
            content.body = "Установите запасной. Списание не возвращено — обратитесь в поддержку. \(detail)"
        }
        content.sound = .default
        // Time-sensitive so it pierces Focus modes the same way the alarm
        // itself does — the user needs to know NOW that there's no re-fire.
        content.interruptionLevel = .timeSensitive

        // Fire ASAP. UNTimeIntervalNotificationTrigger requires > 0; 1s is
        // the minimum that survives the daemon's clamp without being silently
        // dropped, and is imperceptible to the user.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "snooze_schedule_failed_\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request) { fallbackError in
            if let fallbackError = fallbackError {
                // Even the fallback banner failed to register — usually
                // because notification permission was revoked, which is
                // exactly the same root cause the snooze hit. Nothing left
                // to surface from a notification action context.
                AppLogger.appDelegate.fault(
                    "snooze fallback banner failed: \(fallbackError.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    /// Presents an alert on the topmost VC explaining that the alarm fired
    /// but its data couldn't be decoded. Without this surface the user just
    /// hears their alarm cut off with no explanation — silently regressing
    /// the very pattern #117 is fixing.
    private func presentAlarmDataCorruptedAlert(error: Error) {
        let message: String
        if let repoError = error as? AlarmRepository.RepositoryError,
           case let .decodeFailure(detail) = repoError {
            message = "Будильник прозвенел, но его данные повреждены и экран не загрузился. Подробности: \(detail)"
        } else {
            message = "Будильник прозвенел, но его данные не удалось загрузить. Откройте приложение и проверьте список будильников."
        }
        DispatchQueue.main.async {
            guard
                let windowScene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first,
                let rootVC = windowScene.windows.first?.rootViewController
            else {
                AppLogger.appDelegate.error(
                    "decode-failure alert: no window scene to present on"
                )
                return
            }
            var topVC = rootVC
            while let presented = topVC.presentedViewController {
                topVC = presented
            }
            let alert = UIAlertController(
                title: "Будильник",
                message: message,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Ок", style: .default))
            topVC.present(alert, animated: true)
        }
    }
}
