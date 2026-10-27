import UIKit
import os

/// Quiet recovery stays separate from this screen's current firing identity.
extension AlarmFiringViewController {
    func previousOccurrenceRecoveryEntry() -> AlarmOccurrenceRecoveryEntry? {
        guard let occurrenceRecovery else { return nil }
        do {
            return try occurrenceRecovery.pendingFinishes().first {
                $0.ticket.alarmID == viewModel.alarm.id && $0.differs(from: viewModel.snoozeReference)
            }
        } catch {
            AppLogger.emit(.ui, .error, "Pending occurrence discovery unavailable on firing screen")
            return nil
        }
    }

    func retryPreviousOccurrence(_ ticket: AlarmOccurrenceFinishTicket, from alert: UIAlertController? = nil) {
        guard previousOccurrenceRecoveryEntry()?.ticket == ticket else { return }
        let perform = { [weak self] in
            guard let self, let recovery = self.occurrenceRecovery,
                  self.previousOccurrenceRecoveryEntry()?.ticket == ticket else { return }
            AlarmOccurrenceRecoveryAlerts.perform(ticket, on: self, recovery: recovery)
        }
        if let alert {
            guard presentedViewController === alert else { return }
            alert.dismiss(animated: true, completion: perform)
        } else {
            guard presentedViewController == nil else { return }
            perform()
        }
    }

    func presentOccurrenceFinishError(_ error: AlarmOccurrenceFinishError) {
        AppLogger.emit(.ui, .error, "Occurrence finish unconfirmed: \(String(describing: error))")
        let alert = UIAlertController(
            title: Localized.text("firing.finish.error.title"),
            message: Localized.text("firing.finish.error.message"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: Localized.text("firing.finish.retry"), style: .default) { [weak self] _ in
            self?.retryOccurrenceFinish()
        })
        if let previous = previousOccurrenceRecoveryEntry() {
            alert.addAction(UIAlertAction(
                title: Localized.text("firing.finish.recovery.previous"), style: .default
            ) { [weak self, weak alert] _ in
                guard let alert else { return }
                self?.retryPreviousOccurrence(previous.ticket, from: alert)
            })
        }
        alert.addAction(UIAlertAction(title: Localized.text("common.button.close"), style: .cancel))
        present(alert, animated: true)
    }

    private func retryOccurrenceFinish() {
        if let alert = presentedViewController as? UIAlertController {
            alert.dismiss(animated: true) { [weak self] in self?.dismissTapped() }
        } else {
            dismissTapped()
        }
    }

}
