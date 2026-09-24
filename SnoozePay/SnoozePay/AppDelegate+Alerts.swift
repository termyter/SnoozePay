//
//  AppDelegate+Alerts.swift
//  SnoozePay
//

import UIKit
import os

// MARK: - Alert presentation
//
// Extracted from `AppDelegate.swift` (#813) so the host file stays under
// SwiftLint's `file_length` cap. Only the static, test-driven half moved: the
// instance entry points that locate a presenter
// (`presentNotificationsDisabledAlert()`, `presentAlarmDataCorruptedAlert(error:)`)
// stay with their `private` callers. Behaviour is verbatim — only the physical
// location moved.

extension AppDelegate {

    // MARK: Notifications-disabled alert (#789, #805)

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
    /// `presentedViewController` back, which names no reason but covers every
    /// refusal `present` declines outright. Neither sees a presentation that
    /// starts and does not finish — torn down or stalled — which leaves no
    /// line for as long as the completion has not run, here as in #752.
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
    ///
    /// The guard's three refusals are transient, so each earns one retry (#805);
    /// the read-back drops at once, as its cause is unknown.
    static func showNotificationsDisabledAlert(on topVC: UIViewController, retriesLeft: Int = 1) {
        let message = Localized.text("permissions.alert.notifications_disabled.message")
        // No caller passes 0: 0 means this call IS the retry.
        let retried = retriesLeft == 0 ? " after one retry" : ""
        if let reason = presentationRefusalReason(presenter: topVC) {
            if retriesLeft > 0 {
                AppLogger.emit(.appDelegate, .info, "Notifications-disabled alert deferred — \(reason); retrying")
                scheduleNotificationsAlertRetry { relocated in
                    showNotificationsDisabledAlert(on: relocated ?? topVC, retriesLeft: retriesLeft - 1)
                }
                return
            }
            AppLogger.emit(
                .appDelegate, .error,
                notificationsDisabledDroppedLine(reason: reason + retried, message: message)
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
                    reason: "\(type(of: topVC)) did not put the alert up\(retried)",
                    message: message
                )
            )
            return
        }
    }

    /// Runs the retry (#805) on a timer: `UIScene.didActivateNotification` does
    /// not come if the scene is already active. A seam so tests run it by hand.
    static var scheduleNotificationsAlertRetry: (@escaping (UIViewController?) -> Void) -> Void = { retry in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            retry(AppDelegate.notificationsAlertRetryPresenter(from: ActiveWindowLocator.rootViewController()))
        }
    }

    /// The presenter the retry gets: the topmost controller over the located
    /// root, or `nil` — after logging the locator's own reason, since a drop
    /// line that may follow can only name the original presenter's (#797).
    static func notificationsAlertRetryPresenter(
        from located: Result<UIViewController, ActiveWindowLocator.Miss>
    ) -> UIViewController? {
        switch located {
        case let .success(root):
            return topmostPresenter(from: root)
        case let .failure(miss):
            AppLogger.emit(.appDelegate, .info, "Notifications-disabled retry: \(miss.rawValue); reusing the presenter")
            return nil
        }
    }

    /// `root`, or the last controller in its chain of presentations.
    static func topmostPresenter(from root: UIViewController) -> UIViewController {
        var topVC = root
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        return topVC
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

    // MARK: Corrupt-data alert (#752)

    /// Grep handle for the line written once the corrupt-data alert is on
    /// screen. Paired with ``alertDroppedErrorID`` so "the user was told" and
    /// "the telling never happened" are two searches rather than one ambiguous
    /// line — the split `StatisticsViewModel` already carries for its own
    /// load-error alert (#721/#731).
    static let alertShownErrorID = "ALARM-752-ALERT-SHOWN"

    /// Grep handle for the line written when the alert could not be shown.
    static let alertDroppedErrorID = "ALARM-752-ALERT-DROPPED"

    /// Grep handle for the line written when the same alert is already up.
    static let alertAlreadyShownErrorID = "ALARM-864-ALERT-ALREADY-SHOWN"

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
    /// say why but covers every refusal `present` declines outright. The first
    /// alone left every refusal outside its list of three producing no alert
    /// and no line, which is the complaint of #752 verbatim. Neither sees a
    /// presentation that starts and does not finish — torn down or stalled.
    static func showAlarmDataCorruptedAlert(on topVC: UIViewController, message: String) {
        // The caller walks to the topmost controller, so an identical alert
        // still on screen is `topVC` itself. A tap on the #860 banner resolves
        // the same corrupt store again; a second alert says nothing new (#864).
        // One on its way out does not count: the user is about to lose it.
        // `.default` is notice level, which sysdiagnose keeps and `.info` is not.
        if let shown = topVC as? UIAlertController, shown.message == message, !shown.isBeingDismissed {
            AppLogger.emit(
                .appDelegate, .default,
                "[\(alertAlreadyShownErrorID)] Alarm data-corrupted alert already on screen"
            )
            return
        }
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
    /// leaves a record where UIKit leaves none. That holds because `topVC` is
    /// the TOPMOST controller: for a child whose ancestor is on screen, UIKit
    /// may present through the ancestor, which is why `Statistics` asks these
    /// questions only after `present` has refused (#790). The guard `Statistics` needs —
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
    /// ⚠️ Same name and label as
    /// ``StatisticsViewController/droppedAlertDiagnostic(presenter:message:)``,
    /// and the same argument — the controller that WOULD present — but not the
    /// same question: that one reports only a stacked alert, because its
    /// caller must not decide the window refusals up front (#790).
    static func droppedAlertDiagnostic(
        presenter topVC: UIViewController, message: String
    ) -> String? {
        guard let reason = presentationRefusalReason(presenter: topVC) else { return nil }
        return droppedAlertLine(reason: reason, message: message)
    }

    /// Why `topVC` would refuse to present, or `nil` when it is free to.
    ///
    /// Shared by both alerts here and by `StatisticsViewController`'s
    /// post-refusal line rather than listed three times: a fourth state added
    /// to one copy and not to another is a state one alert reports and another
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

    /// What `AlarmFiringPresenter.reportDataCorrupted` does by default: hand
    /// the error to the application's `AppDelegate`, which puts the alert up.
    ///
    /// A delegate of any other type cannot, and until #872 that was a silent
    /// `?.`: the alert never went up and nothing said so. Unreachable in
    /// production, where the delegate is always `AppDelegate`; it takes the
    /// delegate as a parameter so a test can reach the other branch.
    static func forwardAlarmDataCorrupted(_ error: Error, to delegate: UIApplicationDelegate?) {
        guard let appDelegate = delegate as? AppDelegate else {
            let found = delegate.map { String(describing: type(of: $0)) } ?? "nil"
            AppLogger.emit(
                .appDelegate, .error,
                "[\(AppDelegate.alertDroppedErrorID)] Alarm data-corrupted alert dropped — "
                    + "application delegate is \(found), not AppDelegate. Error: \(String(describing: error))"
            )
            return
        }
        appDelegate.reportAlarmDataCorrupted(error)
    }
}
