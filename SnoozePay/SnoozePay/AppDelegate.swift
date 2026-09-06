//
//  AppDelegate.swift
//  SnoozePay
//

import UIKit
import UserNotifications
import os

/// Reference-typed holder for an `NSObjectProtocol` observer token so a
/// `@Sendable` notification closure can read/clear it without the captured
/// variable being mutated after capture (Swift 6 strict-concurrency warning).
/// The observer token itself is only ever touched on the main queue (the
/// observer is added with `queue: .main` and only the closure mutates the
/// field), so `@unchecked Sendable` is sound here.
private final class ObserverBox: @unchecked Sendable {
    var token: NSObjectProtocol?
}

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    /// Tokens for the time-change / activation observers that drive alarm
    /// re-arming (#427). Held for the app's lifetime so the observers stay
    /// registered; the `AppDelegate` lives as long as the process, so they are
    /// never explicitly removed.
    private var rescheduleObserverTokens: [NSObjectProtocol] = []

    /// Token for the resume-audio-failure observer (#405). Held for the app's
    /// lifetime alongside `rescheduleObserverTokens`.
    private var resumeAudioObserverToken: NSObjectProtocol?

    /// Latch so a persistent re-arm failure surfaces a banner only once per
    /// episode rather than on every foreground (#442). Reset to 0 by a fully-
    /// successful re-arm.
    private var lastRescheduleFailedCount = 0

    /// `true` when this process was started by the DEBUG screen router
    /// (`-uitour <screen>`). Always `false` in RELEASE — the whole tour is
    /// compiled out — so the launch-time behaviour a shipped build gets is
    /// unchanged by construction, not by convention.
    private static var isUITourLaunch: Bool {
        #if DEBUG
        return UITourLauncher.isTourLaunch(arguments: ProcessInfo.processInfo.arguments)
        #else
        return false
        #endif
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        #if DEBUG
        // Before ANY scheduler call: `-uitour-alarmkit granted|denied` decides
        // what AlarmKit answers for this launch (#606). `requestPermission`
        // below would otherwise reach the real backend, whose prompt is both
        // unanswerable from a UI test and able to cover the screen mid-run.
        // `SceneDelegate`'s tour mount re-applies it; the call is idempotent.
        UITourLauncher.applyForcedAlarmKitBackend()
        #endif

        // Register notification categories on every cold launch so the actions
        // of a notification left pending by a pre-#472 build stay wired up.
        AlarmScheduler.shared.registerCategories()
        // Defer the permission prompt until the dedicated
        // PermissionsViewController has had a chance to drive it (#149) —
        // otherwise the OS dialog would race the splash → onboarding →
        // permissions UI and the user sees the system prompt before the
        // explanatory screen. Once Permissions has been shown at least once,
        // the auto-request resumes for subsequent launches so the existing
        // "permission revoked from Settings" alert keeps firing.
        //
        // A `-uitour` launch is excluded (#626). The tour mounts ONE screen
        // directly and must never put a dialog over it — the same contract
        // `UITourAlarmKitBackend` states for the system prompt. The re-ask here
        // broke it transitively: `OnboardingFlowUITests` taps «Готово», which
        // flips `hasBeenShown` in the simulator's UserDefaults, and every tour
        // launch after it in the same run asked again, was refused, and covered
        // the mounted screen with «Уведомления выключены» — an alert the test
        // never asked for and could only hope XCUITest would swat away in time.
        if PermissionsViewController.hasBeenShown, !AppDelegate.isUITourLaunch {
            AlarmScheduler.shared.requestPermission { [weak self] granted in
                if !granted {
                    AppLogger.appDelegate.notice("alarm permission denied — alarms will not fire")
                    self?.presentNotificationsDisabledAlert()
                }
            }
        }

        // Eagerly construct StoreKitService so its Transaction.updates listener
        // starts at app launch — otherwise deferred Ask-to-Buy approvals / refunds
        // pile up unprocessed until the user opens TopUp.
        _ = StoreKitService.shared

        // Rebuild the paid part of the wallet when this install has none — a
        // reinstall or a new device (#364). No-op on every launch after the
        // first: `restoreIfNeeded()` returns immediately unless the wallet is
        // pristine, and each transaction is credited at most once via the
        // StoreKit dedup table.
        Task { await TopUpRestoreService.shared.restoreIfNeeded() }

        // Handle notification responses
        UNUserNotificationCenter.current().delegate = self

        // Watch AlarmKit's alerting stream so an alarm that fires while the app
        // is in the foreground mounts our custom firing screen on top of the
        // system alert (#379). No-op on iOS < 26 / when AlarmKit is absent.
        AlarmKitAlertObserver.shared.start()

        // Re-arm saved alarms whenever the wall-clock interpretation of their
        // triggers may have shifted (timezone / DST change, reboot) or the
        // AlarmKit grant that arms them may have been toggled in Settings.
        // Without this, alarms keep whatever schedule they had at save time and
        // silently fire at the wrong time (#427). The first foreground after
        // launch covers reboot.
        registerAlarmRescheduleObservers()

        // Surface a silent resume-time audio failure as a lock-screen banner
        // (#405). When the audio session can't be re-activated on resume and the
        // firing screen isn't visible, the in-app banner never reaches the user;
        // this observer turns AudioService's process notification into a
        // time-sensitive local notification they actually see.
        registerResumeAudioFailedObserver()

        // Reclaim orphaned custom-theme JPEGs (#357): re-picking a photo or
        // deleting a `.custom`-themed alarm leaves its image on disk forever.
        // Sweep off the main thread against the live alarm set — only files no
        // current alarm references are removed.
        // The read is CHECKED (#271): with the lossy `fetchAll()` a corrupt
        // store decoded to `[]`, which the sweep reads as "nothing is
        // referenced" and deletes every custom theme photo — permanent loss
        // caused by a recoverable decode glitch.
        DispatchQueue.global(qos: .utility).async {
            AlarmThemeImageStore.reconcileCaches(
                readingAlarms: { try AlarmRepository.shared.fetchAllChecked() }
            )
        }

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

    // MARK: - Alarm re-arming (#427)

    /// Observe the two system signals that can silently invalidate already
    /// scheduled alarm triggers and re-arm every saved alarm in response:
    ///
    /// - `significantTimeChangeNotification` — posted on timezone change, DST
    ///   transition, and midnight rollover. This is the primary defence against
    ///   an alarm firing at the wrong wall-clock after the user crosses a
    ///   timezone or the clocks shift.
    /// - `didBecomeActiveNotification` — posted on every foreground, including
    ///   the first one after a cold launch (so reboot is covered) and after the
    ///   user returns from Settings having toggled AlarmKit / notification
    ///   permission (so `usesAlarmKit` is re-evaluated and the alarm moves to
    ///   the correct backend).
    ///
    /// Re-arming is idempotent — for an unchanged alarm `cancel` + `schedule`
    /// re-adds the same deterministic notification identifiers — so firing it on
    /// every activation only recomputes triggers, never duplicates them.
    private func registerAlarmRescheduleObservers() {
        let names: [Notification.Name] = [
            UIApplication.significantTimeChangeNotification,
            UIApplication.didBecomeActiveNotification
        ]
        rescheduleObserverTokens = names.map { name in
            NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.rescheduleSavedAlarms(trigger: name)
            }
        }
    }

    /// Re-arm every saved alarm against the current clock / timezone / backend,
    /// then surface an aggregate banner if any failed to re-arm (#442). Instance
    /// method (was `static`) so the outcome can be deduped via
    /// `lastRescheduleFailedCount`; the observer captures `self` weakly.
    private func rescheduleSavedAlarms(trigger: Notification.Name) {
        AppLogger.appDelegate.info(
            "re-arming saved alarms (trigger=\(trigger.rawValue, privacy: .public))"
        )
        // Checked read (#271). The lossy `fetchAll()` handed `rescheduleAll` an
        // empty list on a corrupt store, which reports `failedCount == 0` —
        // "everything re-armed" while nothing was armed at all, AND that zero
        // cleared the #442 latch, so a genuine earlier failure stopped being
        // reported too. An unreadable store is not evidence of success: skip
        // the re-arm and leave the latch as it was. The corruption itself is
        // surfaced to the user by `AlarmsListViewModel.loadData()`.
        let saved: [Alarm]
        do {
            saved = try AlarmRepository.shared.fetchAllChecked()
        } catch {
            AppLogger.appDelegate.fault(
                "re-arm skipped: alarm store unreadable (\(String(describing: error), privacy: .public))"
            )
            return
        }
        AlarmScheduler.shared.rescheduleAll(saved) { [weak self] failedCount in
            self?.handleRescheduleOutcome(failedCount: failedCount)
        }
    }

    /// Surface a re-arm failure ONCE per episode: post a banner when failures
    /// first appear and stay quiet until a fully-successful re-arm (count 0)
    /// clears the latch, so a persistent failure (e.g. revoked permission)
    /// doesn't banner on every foreground (#442).
    private func handleRescheduleOutcome(failedCount: Int) {
        defer { lastRescheduleFailedCount = failedCount }
        guard failedCount > 0, lastRescheduleFailedCount == 0 else { return }
        AppLogger.appDelegate.fault(
            "rescheduleAll: \(failedCount, privacy: .public) alarms failed to re-arm"
        )
        Self.postRescheduleFailedBanner(failedCount: failedCount)
    }

    /// Observe `AudioService.resumeAudioFailedNotification` so a silent
    /// resume-time audio failure is surfaced as a lock-screen banner even when
    /// no firing screen is visible (#405). `static` handler so the `@Sendable`
    /// closure doesn't capture `self`.
    private func registerResumeAudioFailedObserver() {
        resumeAudioObserverToken = NotificationCenter.default.addObserver(
            forName: AudioService.resumeAudioFailedNotification,
            object: nil,
            queue: .main
        ) { _ in
            AppDelegate.postResumeAudioFailedBanner()
        }
    }

    /// Post a time-sensitive local notification telling the user their alarm
    /// is sounding silently because the audio session could not be reclaimed on
    /// resume. Mirrors `postSnoozeScheduleFailedBanner` — a banner the system
    /// delivers is the only surface that reaches a user who isn't looking at
    /// the firing screen (#405).
    private static func postResumeAudioFailedBanner() {
        let content = UNMutableNotificationContent()
        content.title = "Будильник звучит беззвучно"
        content.body = "Не удалось включить звук — откройте приложение и выключите будильник вручную."
        content.sound = .default
        // Time-sensitive so it pierces Focus the way the alarm itself would.
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "resume_audio_failed_\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                AppLogger.appDelegate.fault(
                    "resume-audio-failed banner failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    /// Post a time-sensitive local notification when one or more alarms failed
    /// to re-arm on a clock/timezone/reboot/permission change (#442). The re-arm
    /// runs in the background (no UI on screen), so a system-delivered banner is
    /// the only surface that reaches the user.
    private static func postRescheduleFailedBanner(failedCount: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Будильники не перевзведены"
        content.body = "Не удалось перепланировать будильники (\(failedCount)) — "
            + "откройте приложение и проверьте разрешения на уведомления."
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "reschedule_failed_\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                AppLogger.appDelegate.fault(
                    "reschedule-failed banner failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    // MARK: - Permission UI

    private func presentNotificationsDisabledAlert() {
        DispatchQueue.main.async { [weak self] in
            // Cold-start: permission callback may fire before SceneDelegate attaches
            // the window. Defer until a scene becomes active rather than dropping silently.
            let rootVC: UIViewController
            switch ActiveWindowLocator.rootViewController() {
            case let .success(located):
                rootVC = located
            case let .failure(miss):
                // The locator's own sentence rather than "no rootVC yet": only
                // one of its three states is the cold-launch race the retry
                // below waits out, and the old line read the same under all
                // three (#797).
                AppLogger.appDelegate.info(
                    "deferring notifications-disabled alert — \(miss.rawValue, privacy: .public)"
                )
                self?.deferNotificationsDisabledAlertUntilSceneActive()
                return
            }

            var topVC = rootVC
            while let presented = topVC.presentedViewController {
                topVC = presented
            }
            // `AppDelegate.` rather than `Self.`, as at the corrupt-data call
            // site: `Self` inside an instance method would capture `self`.
            AppDelegate.showNotificationsDisabledAlert(on: topVC)
        }
    }

    private func deferNotificationsDisabledAlertUntilSceneActive() {
        // The observer token must be assigned AFTER `addObserver` returns, but
        // the closure also needs to read it to call `removeObserver` on first
        // fire. Capturing a `var` directly trips Swift's sendable-closure
        // diagnostic ("'observer' mutated after capture by sendable closure"),
        // which is a real race-condition signal under strict concurrency. We
        // route the token through a tiny reference box so the closure captures
        // the box (immutable reference) and reads/writes the field at fire
        // time — no captured-var mutation, semantically identical lifecycle.
        let box = ObserverBox()
        box.token = NotificationCenter.default.addObserver(
            forName: UIScene.didActivateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            if let token = box.token {
                NotificationCenter.default.removeObserver(token)
                box.token = nil
            }
            self?.presentNotificationsDisabledAlert()
        }
    }

    /// Grep handle for the line written once the notifications-disabled alert
    /// is on screen; ``notificationsAlertDroppedErrorID`` is its pair.
    ///
    /// Its own number rather than #752's: that incident is the corrupt-data
    /// alert, and one handle covering both would answer "was the user warned"
    /// with lines about a different alert.
    static let notificationsAlertShownErrorID = "ALARM-789-ALERT-SHOWN"

    /// Grep handle for the line written when the warning never reached anyone.
    static let notificationsAlertDroppedErrorID = "ALARM-789-ALERT-DROPPED"

    /// Puts the notifications-disabled alert on `topVC`, or writes down that
    /// the user was never warned (#789).
    ///
    /// Static and taking its presenter, like
    /// ``showAlarmDataCorruptedAlert(on:message:)``: the caller resolves the
    /// presenter through `UIApplication.shared.connectedScenes`, which a unit
    /// test cannot stage, and everything worth asserting happens after that.
    ///
    /// The drop is decided twice, the shape #752 arrived at: once before
    /// `present`, where the reason can be named, and once after it by reading
    /// `presentedViewController` back, which names no reason but misses no
    /// refusal. This alert says alarms will not fire at all, so a refusal that
    /// leaves neither an alert nor a line is the worse of the two silences.
    ///
    /// ⚠️ The title's words are load-bearing outside this file:
    /// `CreateAlarmUITests` finds this alert as `app.alerts["Уведомления
    /// выключены"]`, and E2E only runs behind the `ui-test` label — so a
    /// reworded value would go red on some later PR instead of the one that
    /// changed it. `AppDelegateAlertTests` pins the words in the unit suite,
    /// which always runs.
    ///
    /// Catalogue copy since #752. These two button titles were the last
    /// literal `UIAlertAction` titles in the app at that point: #664 swept the
    /// ones that read as acknowledgements, and «Отмена»/«Настройки» are
    /// neither, so its scan passed over them by design rather than by oversight.
    static func showNotificationsDisabledAlert(on topVC: UIViewController) {
        let message = Localized.text("permissions.alert.notifications_disabled.message")
        if let reason = presentationRefusalReason(presenter: topVC) {
            AppLogger.emit(
                .appDelegate, .error,
                notificationsDisabledDroppedLine(reason: reason, message: message)
            )
            return
        }

        let alert = UIAlertController(
            title: Localized.text("permissions.alert.notifications_disabled.title"),
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: Localized.text("common.button.cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: Localized.text("common.button.settings"), style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        })

        // From the completion, not before the call: UIKit answers a
        // presentation it cannot perform by doing nothing, so a line written
        // ahead of `present` claims a warning the user may never have seen.
        topVC.present(alert, animated: true) {
            AppLogger.emit(
                .appDelegate, .error,
                """
                [\(AppDelegate.notificationsAlertShownErrorID)] Notifications-disabled alert \
                shown to the user: \(message)
                """
            )
        }

        // The guard above names three refusals; UIKit has more and does not
        // publish them, and for those `present` returns having called no
        // completion — no alert, no line. Read back rather than timed:
        // `presentedViewController` is assigned inside `present`, before the
        // completion runs, so this needs no run loop.
        guard topVC.presentedViewController === alert else {
            AppLogger.emit(
                .appDelegate, .error,
                notificationsDisabledDroppedLine(
                    reason: "\(type(of: topVC)) did not put the alert up",
                    message: message
                )
            )
            return
        }
    }

    /// The line to log when the notifications-disabled warning never reached
    /// the user: the grep handle, why, and the warning that was lost.
    ///
    /// Both drop sites go through it for the reason
    /// ``droppedAlertLine(reason:message:)`` exists on the other alert — the
    /// drops are found by one grep or by none.
    static func notificationsDisabledDroppedLine(reason: String, message: String) -> String {
        """
        [\(AppDelegate.notificationsAlertDroppedErrorID)] Notifications-disabled alert dropped — \(reason). \
        Unshown warning: \(message)
        """
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
        // Volume + fade-in (#150) come from the payload, which decodes them
        // optionally so a pre-#150 notification still rings at full volume.
        AudioService.shared.startAlarmSound(
            soundID: payload.soundID,
            alarmID: payload.alarmID,
            volume: payload.volume ?? 1.0,
            fadeIn: payload.volumeFadeIn ?? false
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
            // Explicit "Выключить" on the alarm notification == the user got
            // up — record the wake day for the statistics heatmap (#235),
            // mirroring AlarmFiringViewModel.dismiss() on the in-app path.
            WakeEventStore.shared.recordWake()

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

        // The window/VC walk + full-screen present (and the stacking-alarm
        // swap) live in `AlarmFiringPresenter` so the AlarmKit paths (#379)
        // share them verbatim. Keep the hop to the main queue here: the
        // notification delegate already runs on main, but `willPresent` may
        // race a not-yet-attached window on cold launch.
        DispatchQueue.main.async {
            AlarmFiringPresenter.shared.present(alarm: alarm, snoozeCount: payload.snoozeCount)
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
        content.title = "Откладывание не запланировано"
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
            let rootVC: UIViewController
            switch ActiveWindowLocator.rootViewController() {
            case let .success(located):
                rootVC = located
            case let .failure(miss):
                // Same shape as the other two drops, on purpose. This is the
                // third way the alert never reaches the user, and until the
                // second round of #752 it was the one the promised grep did not
                // find: the line existed but carried neither
                // ``alertDroppedErrorID`` nor the message. A reader who greps
                // the handle and finds nothing concludes «the alert was shown».
                //
                // The reason is the locator's rather than a sentence spelled
                // here: one «no window to present on» would fold cold launch
                // (no scene at all), a scene without windows, and windows
                // without a root into a single line, and a reader who fixes by
                // the reason would go hunting rootless windows in a process
                // that has no windows at all.
                AppLogger.emit(
                    .appDelegate, .error,
                    AppDelegate.droppedAlertLine(reason: miss.rawValue, message: message)
                )
                return
            }
            var topVC = rootVC
            while let presented = topVC.presentedViewController {
                topVC = presented
            }
            // `AppDelegate.` rather than `Self.`: inside an instance method
            // `Self` is the dynamic type, which would make this closure capture
            // `self` — nothing else in it does.
            AppDelegate.showAlarmDataCorruptedAlert(on: topVC, message: message)
        }
    }

    /// Grep handle for the line written once the corrupt-data alert is on
    /// screen. Paired with ``alertDroppedErrorID`` so "the user was told" and
    /// "the telling never happened" are two searches rather than one ambiguous
    /// line — the split `StatisticsViewModel` already carries for its own
    /// load-error alert (#721/#731).
    static let alertShownErrorID = "ALARM-752-ALERT-SHOWN"

    /// Grep handle for the line written when the alert could not be shown.
    static let alertDroppedErrorID = "ALARM-752-ALERT-DROPPED"

    /// Puts the corrupt-data alert on `topVC`, or — when `topVC` cannot present
    /// it — writes down which message the user never got (#752).
    ///
    /// Split out of ``presentAlarmDataCorruptedAlert(error:)`` so the
    /// presentation is drivable from a test: the caller resolves its presenter
    /// through `UIApplication.shared.connectedScenes`, which a unit test cannot
    /// stage, and everything worth asserting happens after that.
    ///
    /// Both lines go through ``AppLogger/emit(_:_:_:)`` rather than
    /// `AppLogger.appDelegate`, so a test can read them back. That matters most
    /// for the drop: it is invisible by construction — nothing appears on
    /// screen — so the line is the only evidence the branch ran. `.appDelegate`
    /// and not `.ui`, because the rest of this incident's trail (the fetch
    /// failure at the call site, the missing window scene above) is filed
    /// there, and one grep should return the whole story.
    ///
    /// The drop is decided TWICE: once before `present` by
    /// ``droppedAlertDiagnostic(presenter:message:)``, which can say why, and
    /// once after it by reading `presentedViewController` back, which cannot
    /// say why but misses nothing. Only the pair closes #752 — the first alone
    /// left every refusal outside its list of three producing no alert and no
    /// line, which is the complaint verbatim.
    static func showAlarmDataCorruptedAlert(on topVC: UIViewController, message: String) {
        if let diagnostic = droppedAlertDiagnostic(presenter: topVC, message: message) {
            AppLogger.emit(.appDelegate, .error, diagnostic)
            return
        }

        let alert = UIAlertController(
            title: "Будильник",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: Localized.text("common.button.ok"), style: .default))
        // From the completion, not before the call. UIKit answers a
        // presentation it cannot perform by doing nothing and saying so only in
        // its own log, so a line written ahead of `present` would assert an
        // alert the user may never have seen — the same defect the guard above
        // exists to close, pointing the other way (#721/#731).
        topVC.present(alert, animated: true) {
            AppLogger.emit(
                .appDelegate, .error,
                "[\(AppDelegate.alertShownErrorID)] Alarm data-corrupted alert shown to the user: \(message)"
            )
        }

        // The guard above names three refusals; UIKit has more, and does not
        // publish them. For any of the others `present` returns having done
        // nothing and called nothing — no alert, no completion, and therefore
        // no line at all. That left #752 closed for three states and open for
        // the rest: an alert stacked onto an already-presented
        // `UIAlertController` (the walk in the caller ends ON one whenever the
        // notifications-disabled alert is up) passes every check above and can
        // still go nowhere.
        //
        // Read back rather than timed: UIKit assigns `presentedViewController`
        // synchronously inside `present`, before the completion runs, so this
        // needs no run loop and cannot flake. That assumption is load-bearing,
        // so it is asserted rather than trusted —
        // `testCorruptDataAlert_onAMountedPresenter_logsThatTheUserSawIt`
        // fails on a DROPPED line for an alert it watches appear, which is
        // exactly what a wrong assumption would produce here.
        guard topVC.presentedViewController === alert else {
            AppLogger.emit(
                .appDelegate, .error,
                AppDelegate.droppedAlertLine(
                    reason: "\(type(of: topVC)) did not put the alert up",
                    message: message
                )
            )
            return
        }
    }

    /// The line to log when the corrupt-data alert cannot be shown, or `nil`
    /// when `topVC` is free to show it.
    ///
    /// A pure function rather than an inline `guard` body so the message — the
    /// entire remedy for a dropped alert — can be asserted without staging a
    /// live presentation, which is the shape `StatisticsViewController` already
    /// uses.
    ///
    /// The three refusals it names are states where `present` is a no-op anyway, so
    /// declining costs no alert that would otherwise have appeared; it only
    /// leaves a record where UIKit leaves none. The guard `Statistics` needs —
    /// "something is already presented" — is deliberately absent: the caller
    /// walks to the topmost controller first, so `presentedViewController` is
    /// nil by construction and this alert stacks on top of whatever is up
    /// rather than fighting it.
    ///
    /// ⚠️ The list is not exhaustive and cannot be: UIKit refuses for reasons it
    /// does not publish. That is why the caller does NOT rely on this function
    /// alone — it re-reads `presentedViewController` after `present` and covers
    /// every other reason at once. This one still earns its place: it names WHY,
    /// and it is the half a test can drive without a live transition.
    ///
    /// ⚠️ The label is `presenter:`, not `presenting:`. The other function of
    /// this name in the app — ``StatisticsViewController/droppedAlertDiagnostic(presenting:message:)``
    /// — takes the controller that BLOCKS the presentation
    /// (`presentedViewController`); this one takes the controller that WOULD
    /// perform it. The types are compatible, so copying a call from one file to
    /// the other compiles and answers the opposite question. The differing
    /// label is what makes that copy fail to build instead. (#790 tracks
    /// bringing the `Statistics` one up to this shape.)
    static func droppedAlertDiagnostic(
        presenter topVC: UIViewController, message: String
    ) -> String? {
        guard let reason = presentationRefusalReason(presenter: topVC) else { return nil }
        return droppedAlertLine(reason: reason, message: message)
    }

    /// Why `topVC` would refuse to present, or `nil` when it is free to.
    ///
    /// Shared by both alerts rather than listed twice: a fourth state added to
    /// one copy and not to the other is a state one alert reports and the other
    /// drops silently. Only the wrapping line differs, so only that is
    /// duplicated.
    static func presentationRefusalReason(presenter topVC: UIViewController) -> String? {
        if topVC.viewIfLoaded?.window == nil {
            return "\(type(of: topVC)) is not in the window hierarchy"
        }
        if topVC.isBeingDismissed {
            return "\(type(of: topVC)) is being dismissed"
        }
        if topVC.isBeingPresented {
            return "\(type(of: topVC)) is itself still being presented"
        }
        return nil
    }

    /// The single shape every "the user never saw it" line takes: the grep
    /// handle, why, and the sentence that was lost.
    ///
    /// One builder rather than a spelled-out string per call site, because the
    /// drops are found by ONE grep or by none. Three sites reach it: the
    /// missing window scene, the three states
    /// ``droppedAlertDiagnostic(presenter:message:)`` names, and the read-back
    /// after `present` that covers whatever UIKit refuses for reasons it does
    /// not publish. The window-scene one spent the first round of #752 outside
    /// that grep precisely because it spelled out its own sentence.
    static func droppedAlertLine(reason: String, message: String) -> String {
        """
        [\(AppDelegate.alertDroppedErrorID)] Alarm data-corrupted alert dropped — \(reason). \
        Unshown message: \(message)
        """
    }
}
