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

    /// Where the notification paths look up the alarm a payload names
    /// (`resolveFiringAlarm(for:)`). Production never reassigns it; a test
    /// points a fresh `AppDelegate` at a repository over its own defaults
    /// suite, so it can save an alarm without writing `.standard` (#814).
    var alarmRepository: AlarmRepository = .shared

    /// What `resolveFiringAlarm(for:)` does when the repository fails to
    /// decode: put the data-corrupted alert on screen. Production never
    /// reassigns it; a test that drives a decode failure replaces it, so the
    /// alert never mounts on the test host's window (#860).
    lazy var reportAlarmDataCorrupted: (Error) -> Void = { [unowned self] error in
        self.presentAlarmDataCorruptedAlert(error: error)
    }

    /// Where `resolveFiringAlarm(for:)` landed. A miss keeps its reason, so
    /// `willPresent` can let the system ring for a load failure but not for a
    /// deleted alarm (#860).
    fileprivate enum FiringAlarmLookup {
        case found(Alarm)
        case notFound
        case loadFailed
    }

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
    ///
    /// The three banner builders are internal and take `poster` so
    /// `AppBannerPostingTests` can see the request each one posts (#844).
    static func postResumeAudioFailedBanner(
        poster: LocalNotificationPosting = UNUserNotificationCenter.current()
    ) {
        let content = UNMutableNotificationContent()
        content.title = "Будильник звучит беззвучно"
        content.body = "Не удалось включить звук — откройте приложение и выключите будильник вручную."
        content.sound = .default
        // Time-sensitive so it pierces Focus the way the alarm itself would.
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        // Through `emit` so a test can read the line back. `onFailure` runs on
        // the main actor, which `emit` requires, and it writes `.public` as the
        // direct call did.
        poster.postAppBanner(.resumeAudioFailed, content: content, trigger: trigger) { error in
            AppLogger.emit(
                .appDelegate, .fault,
                "resume-audio-failed banner failed: \(error.localizedDescription)"
            )
        }
    }

    /// Post a time-sensitive local notification when one or more alarms failed
    /// to re-arm on a clock/timezone/reboot/permission change (#442). The re-arm
    /// runs in the background (no UI on screen), so a system-delivered banner is
    /// the only surface that reaches the user.
    static func postRescheduleFailedBanner(
        failedCount: Int,
        poster: LocalNotificationPosting = UNUserNotificationCenter.current()
    ) {
        let content = UNMutableNotificationContent()
        content.title = "Будильники не перевзведены"
        content.body = "Не удалось перепланировать будильники (\(failedCount)) — "
            + "откройте приложение и проверьте разрешения на уведомления."
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        poster.postAppBanner(.rescheduleFailed, content: content, trigger: trigger) { error in
            AppLogger.emit(
                .appDelegate, .fault,
                "reschedule-failed banner failed: \(error.localizedDescription)"
            )
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

            // `AppDelegate.` rather than `Self.`, as at the corrupt-data call
            // site: `Self` inside an instance method would capture `self`.
            AppDelegate.showNotificationsDisabledAlert(on: AppDelegate.topmostPresenter(from: rootVC))
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
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {

    // Called when app is in foreground and notification arrives
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // The whole decision lives in `foregroundPresentationOptions(for:startAlarm:)`
        // so a test can drive it with a real `UNNotificationRequest` (#842):
        // `UNNotification` itself cannot be constructed.
        completionHandler(AppDelegate.foregroundPresentationOptions(for: notification.request) { payload in
            self.startForegroundAlarm(payload)
        })
    }

    /// The alarm half of `willPresent`: resolve the alarm, ring, then show the
    /// firing screen.
    ///
    /// The alarm is resolved BEFORE the sound starts (#854). `startAlarmSound`
    /// takes ownership of `AudioService`, so starting it for an alarm that is
    /// not in the repository moved the sound away from whichever firing screen
    /// was ringing, and the stop that followed left that screen silent under a
    /// stale banner. An alarm that does not resolve now never touches the sound.
    ///
    /// Reports how the start went, so `willPresent` can hand the sound to the
    /// system when the app could not ring (#860) — including when the alarm
    /// resolved but plays no sound: a failed session or vibration only (#864).
    /// The state is read after the start: an alarm that takes over a session
    /// already in one of those states is just as silent as one that got there
    /// itself.
    ///
    /// Internal rather than private so a test can drive it through
    /// `foregroundPresentationOptions(for:startAlarm:)`, as `willPresent` does.
    func startForegroundAlarm(_ payload: AlarmNotificationPayload) -> ForegroundAlarmStart {
        let alarm: Alarm
        switch resolveFiringAlarm(for: payload) {
        case let .found(found):
            alarm = found
        case .notFound:
            return .notFound
        case .loadFailed:
            return .loadFailed
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

        presentFiringScreen(for: alarm, snoozeCount: payload.snoozeCount)
        return AppDelegate.foregroundStart(afterStartingIn: AudioService.shared.state)
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
            // AudioService will be started by AlarmFiringViewController.
            // A tap on one of the app's own banners opens the app and nothing
            // else: it must not silence an alarm that is ringing (#842).
            AppDelegate.handleDefaultTap(
                on: response.notification.request,
                presentAlarm: { self.presentAlarmFiringScreen(for: $0) },
                stopAlarmSound: { AudioService.shared.stopAlarmSound() }
            )

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
                self?.handleSnoozeOutcome(outcome)
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
        let ownerHandle = Self.logHandle(owner)
        let payloadHandle = Self.logHandle(payload.alarmID)
        guard owner == payload.alarmID else {
            let decision = "skipping stop — audio owned by \(ownerHandle), not by payload alarm \(payloadHandle)"
            AppLogger.appDelegate.notice("\(action, privacy: .public): \(decision, privacy: .public)")
            return
        }
        AppLogger.appDelegate.notice(
            "\(action, privacy: .public): stopping audio — owned by payload alarm \(payloadHandle, privacy: .public)"
        )
        AudioService.shared.stopAlarmSound()
    }

    /// An alarm id as it goes into these lines: its first 8 hex characters,
    /// logged `.public`. Enough to tell the audio owner from the payload's
    /// alarm in a release log, where a `.private` UUID reads `<private>` on
    /// both sides. The convention `PendingPresentation.logHandle` uses.
    /// Internal so the `willPresent` fallback line (#860) uses it too.
    static func logHandle(_ alarmID: UUID?) -> String {
        alarmID.map { String($0.uuidString.prefix(8)) } ?? "nobody"
    }

    // MARK: - Helpers

    /// The default-tap path: show the firing screen, which starts the sound.
    ///
    /// Internal rather than private so a test can drive it through
    /// `handleDefaultTap(on:presentAlarm:stopAlarmSound:)`, as `didReceive` does.
    func presentAlarmFiringScreen(for payload: AlarmNotificationPayload) {
        guard case let .found(alarm) = resolveFiringAlarm(for: payload) else { return }
        presentFiringScreen(for: alarm, snoozeCount: payload.snoozeCount)
    }

    /// The alarm `payload` names, or why there is none, after logging it.
    ///
    /// On a miss it stops only the sound `payload`'s own alarm owns (#854).
    /// That sound has no screen coming that could stop it. Another alarm's
    /// sound belongs to that alarm's firing screen, which is still up and
    /// still ringing: an unconditional stop silenced it with no dismiss, and
    /// the screen, which applies only notes about its own alarm (#851), went
    /// on showing its last banner over the silence.
    private func resolveFiringAlarm(for payload: AlarmNotificationPayload) -> FiringAlarmLookup {
        let alarm: Alarm?
        do {
            // Use the checked variant so a corrupt UserDefaults blob surfaces
            // a logged decode error instead of being indistinguishable from
            // "alarm doesn't exist" — without this we silently bail on a
            // recoverable glitch and the user wonders why the alarm fired
            // but never showed a screen (issue #117).
            alarm = try alarmRepository.fetchChecked(id: payload.alarmID)
        } catch {
            let errorDesc = String(describing: error)
            let handle = Self.logHandle(payload.alarmID)
            AppLogger.appDelegate.error(
                "alarm fetch failed for \(handle, privacy: .public): \(errorDesc, privacy: .public)"
            )
            stopAlarmSoundIfOwner(of: payload, action: "alarm fetch failed")
            // Surface the decode failure to the user — without this the alarm
            // fires with no sound of its own, no firing screen and no diagnostic.
            // The alert is presented from the same dispatch we'd use for the
            // firing screen so it reaches whichever VC is on top.
            reportAlarmDataCorrupted(error)
            return .loadFailed
        }
        guard let alarm else {
            // Audio this alarm owns has no screen coming that could stop it,
            // so stop it. Another alarm's audio is left to its own screen.
            // The line states the miss only: the gate logs what it decided.
            let handle = Self.logHandle(payload.alarmID)
            AppLogger.appDelegate.error("alarm not found (repo returned nil for \(handle, privacy: .public))")
            stopAlarmSoundIfOwner(of: payload, action: "alarm not found")
            return .notFound
        }
        return .found(alarm)
    }

    private func presentFiringScreen(for alarm: Alarm, snoozeCount: Int) {
        // The window/VC walk + full-screen present (and the stacking-alarm
        // swap) live in `AlarmFiringPresenter` so the AlarmKit paths (#379)
        // share them verbatim. Keep the hop to the main queue here: the
        // notification delegate already runs on main, but `willPresent` may
        // race a not-yet-attached window on cold launch.
        //
        // The answer is discarded: when the screen does not go up — no host
        // yet, the launch splash still the root, UIKit declining — the
        // presenter parks the alarm in its pending slot itself, and the next
        // flush raises it (#834). A swap over another firing screen parks it
        // too, before the dismissal starts, unless another alarm already holds
        // the slot (#835).
        DispatchQueue.main.async {
            AlarmFiringPresenter.shared.present(alarm: alarm, snoozeCount: snoozeCount)
        }
    }

    /// What `SNOOZE_ACTION` does with the coordinator's answer: log it, then
    /// tell the user about a failure.
    ///
    /// A load failure posts the snooze-failed banner too (#864): the snooze is
    /// lost exactly as when the schedule fails, and a system banner survives a
    /// cold launch, where an alert over the splash is torn down with it. Its
    /// "refunded" copy is the right one — nothing was charged. The
    /// data-corrupted alert still goes up for the cause; the alert dedup keeps
    /// it from stacking on the one `willPresent` already raised.
    ///
    /// Internal so a test can hand it an outcome and a poster; `didReceive`
    /// cannot be driven.
    func handleSnoozeOutcome(
        _ outcome: AlarmFiringCoordinator.SnoozeOutcome,
        poster: LocalNotificationPosting = UNUserNotificationCenter.current()
    ) {
        logSnoozeOutcome(outcome)
        switch outcome {
        case let .scheduleFailed(error):
            AppDelegate.postSnoozeScheduleFailedBanner(error: error, refundLanded: true, poster: poster)
        case let .scheduleFailedAndRefundFailed(error):
            AppDelegate.postSnoozeScheduleFailedBanner(error: error, refundLanded: false, poster: poster)
        case let .alarmLoadFailed(error):
            AppDelegate.postSnoozeScheduleFailedBanner(
                detail: error.localizedDescription, refundLanded: true, poster: poster
            )
            reportAlarmDataCorrupted(error)
        default:
            break
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
        case .alarmLoadFailed:
            // The coordinator wrote the cause with its error id and handle.
            AppLogger.appDelegate.error("SNOOZE_ACTION: alarm failed to load, snooze skipped — posting fallback banner")
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
    ///
    /// `static` and internal since #844, like the other two builders, so a test
    /// can drive it without an `AppDelegate` instance. It never read `self`.
    static func postSnoozeScheduleFailedBanner(
        error: AlarmScheduler.SchedulingError,
        refundLanded: Bool,
        poster: LocalNotificationPosting = UNUserNotificationCenter.current()
    ) {
        postSnoozeScheduleFailedBanner(
            detail: error.errorDescription ?? error.localizedDescription,
            refundLanded: refundLanded,
            poster: poster
        )
    }

    /// The same banner with its detail line already spelled: a snooze lost to
    /// a load failure has no `SchedulingError` to describe (#864).
    static func postSnoozeScheduleFailedBanner(
        detail: String,
        refundLanded: Bool,
        poster: LocalNotificationPosting = UNUserNotificationCenter.current()
    ) {
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
        poster.postAppBanner(.snoozeScheduleFailed, content: content, trigger: trigger) { fallbackError in
            // Even the fallback banner failed to register — usually because
            // notification permission was revoked, which is exactly the same
            // root cause the snooze hit. Nothing left to surface from a
            // notification action context.
            AppLogger.emit(
                .appDelegate, .fault,
                "snooze fallback banner failed: \(fallbackError.localizedDescription)"
            )
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
}
