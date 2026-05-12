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

    // MARK: Glow breathing

    /// 4s ease-in-out autoreverse opacity pulse on the Dawn background's sun
    /// layer. Driven via CABasicAnimation because the sun is a CAGradientLayer
    /// (not a view). V2 spec retains the "breathing" character from V1 — the
    /// warm radial just lives inside `SPDawnBackgroundView.sunLayer` now.
    func startGlowBreathing() {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 0.55
        animation.toValue = 1.0
        animation.duration = 4.0
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.autoreverses = true
        animation.repeatCount = .infinity
        dawnBackgroundView.sunLayer.add(animation, forKey: "breathing")
    }

    // MARK: Actions

    func snoozeTapped() {
        // scheduleCompletion surfaces a notification-center failure (revoked
        // permission, 64-pending-limit, malformed trigger) so the user
        // doesn't pay for a snooze that will never re-fire (#127 finding).
        let success = viewModel.snooze { [weak self] result in
            guard let self else { return }
            if case let .failure(error) = result {
                self.presentSnoozeScheduleFailureAlert(error: error)
            }
        }
        if success {
            dismiss(animated: true)
        }
    }

    /// Present the firing-time top-up bottom sheet. Public entry point so the
    /// no-balance UX (#140) can wire it into the snooze affordance once the
    /// firing VC rewrite (#138) lands. Pause/resume of the alarm audio +
    /// escalation is owned by the sheet itself via `AlarmFiringCoordinator
    /// .pauseEscalation()`, so callers don't need to coordinate audio state.
    func presentTopUpSheet() {
        let sheet = FiringTopUpBottomSheetViewController()
        present(sheet, animated: true)
    }

    func presentSnoozeScheduleFailureAlert(
        error: AlarmScheduler.SchedulingError
    ) {
        let detail = error.errorDescription ?? error.localizedDescription
        let alert = UIAlertController(
            title: "Откладывание не запланировано",
            message: "\(detail) Будильник не зазвенит повторно — установите запасной.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Ок", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - Time formatter

/// Cached formatter — `updateTime()` runs once per second; rebuilding a
/// `DateFormatter` each tick is ~1ms wasted. Locale fixed to `en_US_POSIX`
/// so `HH:mm` is honoured regardless of the user's region.
enum AlarmFiringTimeFormatter {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }
}
