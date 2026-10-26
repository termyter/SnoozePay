import UIKit
import os

// MARK: - View lifecycle + clock + glow + actions
//
// Extracted from `AlarmFiringViewController.swift` (#182) so the host file
// stays under SwiftLint's `file_length` and `type_body_length` caps. These
// callbacks used to live as instance members on the main type — only the
// physical location moved; behaviour is verbatim.

extension AlarmFiringViewController {

    // MARK: Clock

    func startClockTicker() {
        updateTime()
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateTime()
        }
    }

    func updateTime() {
        timeLabel.text = AlarmFiringTimeFormatter.string(from: Date())
    }

    // MARK: Clock mount animation

    /// Seed the clock's pre-entrance state: invisible, slightly enlarged (a
    /// soft "out-of-focus" proxy for the CA blur the design uses), and sunk
    /// 8pt below its resting position. The prototype's `DawnTime`
    /// (`docs/design/snoozepay-2026-04-27/project/components/SPDawnV3.jsx:48-67` contains "function DawnTime")
    /// fades + blurs + rises the time on mount; CA blur on a live-ticking
    /// label is impractical, so we approximate it with a subtle scale-down +
    /// alpha-up + 8pt rise.
    func prepareClockMountState() {
        timeLabel.alpha = 0
        timeLabel.transform = CGAffineTransform(translationX: 0, y: 8)
            .scaledBy(x: 1.04, y: 1.04)
    }

    /// Play the 800ms fade + blur-to-sharp + 8px rise entrance once the screen
    /// is on-window. Keeps it subtle per the issue's caution.
    func playClockMountAnimation() {
        UIView.animate(
            withDuration: 0.8,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState],
            animations: {
                self.timeLabel.alpha = 1
                self.timeLabel.transform = .identity
            }
        )
    }

    // MARK: Glow breathing

    /// 8s ease-in-out autoreverse opacity pulse on the Dawn background's sun
    /// layer (`docs/design/snoozepay-2026-04-27/project/components/SPDawnV3.jsx:3` contains "медленно дышит (8s").
    /// Driven via CABasicAnimation because the sun is a CAGradientLayer (not
    /// a view). V2 spec retains the "breathing" character from V1 — the warm
    /// radial just lives inside `SPDawnBackgroundView.sunLayer` now.
    func startGlowBreathing() {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 0.55
        animation.toValue = 1.0
        animation.duration = 8.0
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.autoreverses = true
        animation.repeatCount = .infinity
        dawnBackgroundView.sunLayer.add(animation, forKey: "breathing")
    }

    // MARK: Actions

    func snoozeTapped() {
        let warnings = criticalWarnings
        let alarmID = viewModel.alarm.id
        // The Boolean confirms only a debit. A synchronous refusal must never
        // be followed by countdown entry; an asynchronous success owns handoff.
        viewModel.snooze { [weak self] outcome in
            warnings.record(outcome, alarmID: alarmID)
            guard let self else { return }
            switch outcome {
            case .scheduled:
                guard !self.isStoppedByUser else { return }
                self.dismissAfterAlarmKitSnooze()
            case .scheduleFailed, .scheduleFailedAndRefundFailed:
                self.exitSnoozedState()
            }
        }
    }

    /// Close the firing screen after an AlarmKit snooze (#383). The next ring is
    /// a real system alarm: the scheduler already stopped the currently-alerting
    /// alarm and armed the separate snooze trigger, so we must NOT call
    /// `stopSystemAlarm` again here — that would cancel the freshly-armed snooze.
    /// We only silence any in-app audio (guarded by the per-alarm owner check,
    /// mirroring `viewDidDisappear`; a no-op on this path since we never started
    /// it) and dismiss. `viewDidDisappear` re-runs the same guarded stop, so the
    /// audio teardown is idempotent.
    ///
    /// The owner check and the stop are one step (#880), and a skipped stop
    /// leaves a line naming both alarms, like `viewDidDisappear`'s. Internal,
    /// not private, so `AlarmFiringAlarmKitSnoozeStopTests` can reach it.
    func dismissAfterAlarmKitSnooze() {
        let ours = viewModel.alarm.id
        let (stopped, owner) = AudioService.shared.stopAlarmSound(ifOwnedBy: ours)
        if !stopped {
            // `OSLogType` has no `.notice`; `.default` is the same level.
            AppLogger.emit(
                .audio, .default,
                "dismissAfterAlarmKitSnooze: skip stop — owner=\(AppDelegate.logHandle(owner)),"
                    + " ours=\(AppDelegate.logHandle(ours))"
            )
        }
        if let presenter = presentingViewController {
            presenter.dismiss(animated: true)
        } else {
            dismiss(animated: true)
        }
    }

    /// Present the firing-time top-up bottom sheet. Public entry point so the
    /// no-balance UX (#140) can wire it into the snooze affordance once the
    /// firing VC rewrite (#138) lands. Pause/resume of the alarm audio +
    /// escalation is owned by the sheet itself via `AlarmFiringCoordinator
    /// .pauseEscalation()`, so callers don't need to coordinate audio state.
    func presentTopUpSheet() {
        guard !noBalancePurchaseInFlight else { return }
        // Recommend an actual compatible offer for the next progressive charge.
        // The sheet reads its live wallet; package copy makes no snooze forecasts.
        let sheet = FiringTopUpBottomSheetViewController(
            snoozePrice: viewModel.currentPenalty
        )
        present(sheet, animated: true)
    }
}

// MARK: - Time formatter

/// The firing screen's big clock, its snooze targets and the deletion copy —
/// padded hour ("07:00") per the artboard.
///
/// Kept as a named seam because four call sites read from it, but the
/// formatting itself moved to ``WallClockFormatter`` in #628: the
/// `en_US_POSIX` pin this used to carry meant a user on 12-hour time saw
/// "19:00" here while every other clock on their phone said "7:00 PM".
/// Caching still matters — `updateTime()` runs once per second — and now lives
/// with the shared formatter.
enum AlarmFiringTimeFormatter {
    static func string(from date: Date) -> String {
        WallClockFormatter.string(from: date, style: .padded)
    }

    static func string(from alarm: Alarm) -> String {
        WallClockFormatter.string(from: alarm, style: .padded)
    }
}
