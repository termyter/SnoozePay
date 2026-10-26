import UIKit

enum AlarmOccurrenceRecoveryAlerts {
    /// Only the alert is dismissed for Retry. The host firing controller,
    /// its audio owner and presentation queue are deliberately untouched.
    static func perform(
        _ ticket: AlarmOccurrenceFinishTicket, on host: UIViewController,
        recovery: AlarmOccurrenceRecovering, onChange: @escaping () -> Void = {}
    ) {
        guard host.presentedViewController == nil else { return }
        let result = recovery.resume(ticket)
        onChange()
        guard host.presentedViewController == nil else { return }
        let alert: UIAlertController
        switch result {
        case .success:
            alert = UIAlertController(
                title: Localized.text("firing.finish.recovery.confirmed"),
                message: nil, preferredStyle: .alert
            )
        case .failure(let error):
            AppLogger.emit(.ui, .error, "Pending occurrence confirmation failed: \(String(describing: error))")
            let failureAlert = UIAlertController(
                title: Localized.text("firing.finish.error.title"),
                message: Localized.text("firing.finish.error.message"), preferredStyle: .alert
            )
            alert = failureAlert
            failureAlert.addAction(UIAlertAction(
                title: Localized.text("firing.finish.retry"), style: .default
            ) { [weak host, weak failureAlert] _ in
                guard let host, let failureAlert else { return }
                retry(ticket, from: failureAlert, on: host, recovery: recovery, onChange: onChange)
            })
        }
        alert.addAction(UIAlertAction(title: Localized.text("common.button.close"), style: .cancel))
        host.present(alert, animated: true)
    }

    static func retry(
        _ ticket: AlarmOccurrenceFinishTicket, from alert: UIAlertController, on host: UIViewController,
        recovery: AlarmOccurrenceRecovering, onChange: @escaping () -> Void = {}
    ) {
        guard host.presentedViewController === alert else { return }
        alert.dismiss(animated: true) {
            perform(ticket, on: host, recovery: recovery, onChange: onChange)
        }
    }
}
