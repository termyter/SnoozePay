import UIKit
import os

/// Durable FIFO of safety warnings. Replaying one only presents copy; it never
/// replays the snooze, its charge/refund, or audio. Only OK acknowledges it.
@MainActor
final class CriticalWarningCenter {
    struct Warning: Codable, Equatable {
        let id: UUID
        let alarmID: UUID?
        let detail: String
        let refundLanded: Bool

        var title: String { Localized.text("alarm_failure.snooze.title") }
        var message: String {
            Localized.format(
                refundLanded ? "alarm_failure.snooze.body_refunded" : "alarm_failure.snooze.body_charged", detail
            )
        }
    }

    static let shared = CriticalWarningCenter()
    private static let key = "pending_critical_warnings"
    private let defaults: UserDefaults
    private(set) var pending: [Warning] = []
    private weak var visibleAlert: UIAlertController?
    private var retryScheduled = false

    var isForegroundActive = {
        UIApplication.shared.connectedScenes.contains { $0.activationState == .foregroundActive }
    }
    var locateRoot: () -> UIViewController? = {
        let active = UIApplication.shared.connectedScenes.filter { $0.activationState == .foregroundActive }
        return try? ActiveWindowLocator.rootViewController(among: Array(active)).get()
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let stored = defaults.object(forKey: Self.key) else { return }
        guard let data = stored as? Data else {
            preserveUnreadableQueue(stored, reason: "invalid stored type")
            return
        }
        do {
            pending = try JSONDecoder().decode([Warning].self, from: data)
        } catch {
            preserveUnreadableQueue(stored, reason: String(describing: error))
        }
    }

    func record(detail: String, refundLanded: Bool, alarmID: UUID?) {
        pending.append(Warning(id: UUID(), alarmID: alarmID, detail: detail, refundLanded: refundLanded))
        _ = persist(pending) // Before any UIKit/optional-banner attempt.
        // Let the original callback finish its firing-screen teardown first.
        DispatchQueue.main.async { [weak self] in self?.flush() }
    }

    func record(_ outcome: AlarmFiringViewModel.SnoozeScheduleOutcome, alarmID: UUID) {
        switch outcome {
        case .scheduled: break
        case let .scheduleFailed(error):
            record(detail: error.localizedDescription, refundLanded: true, alarmID: alarmID)
        case let .scheduleFailedAndRefundFailed(error):
            record(detail: error.localizedDescription, refundLanded: false, alarmID: alarmID)
        }
    }

    func contains(alarmID: UUID) -> Bool {
        pending.contains { $0.alarmID == alarmID }
    }

    func acknowledge(_ id: UUID) {
        let remaining = pending.filter { $0.id != id }
        if persist(remaining) { pending = remaining }
        retryWhenActive() // Wait for UIKit to finish dismissing OK's alert.
    }

    private func preserveUnreadableQueue(_ stored: Any, reason: String) {
        var backupKey: String
        repeat { backupKey = "\(Self.key)_unreadable_\(UUID())" }
        while defaults.object(forKey: backupKey) != nil
        defaults.set(stored, forKey: backupKey)
        AppLogger.emit(.appDelegate, .fault, "Critical warnings unreadable (\(reason)); preserved as \(backupKey)")
        // A new known warning can now replace the unreadable active queue safely.
    }

    private func persist(_ warnings: [Warning]) -> Bool {
        do {
            defaults.set(try JSONEncoder().encode(warnings), forKey: Self.key)
            return true
        } catch {
            AppLogger.emit(
                .appDelegate, .fault, "Critical warning queue not saved; retaining pending warnings: \(error)"
            )
            return false
        }
    }

    func flush() {
        guard !pending.isEmpty, isForegroundActive() else { return }
        // Also recover from an unacknowledged alert being torn down while active.
        defer { retryWhenActive() }
        guard let root = locateRoot(), !(root is SplashViewController) else { return }
        let top = AppDelegate.topmostPresenter(from: root)
        guard top !== visibleAlert, visibleAlert?.viewIfLoaded?.window == nil else { return }
        guard !(top is UIAlertController), root.transitionCoordinator == nil,
              top.transitionCoordinator == nil,
              AppDelegate.presentationRefusalReason(presenter: top) == nil else { return }
        present(pending[0], on: top)
    }

    private func present(_ warning: Warning, on presenter: UIViewController) {
        let alert = UIAlertController(title: warning.title, message: warning.message, preferredStyle: .alert)
        alert.isModalInPresentation = true
        alert.addAction(UIAlertAction(title: Localized.text("common.button.ok"), style: .default) { [self] _ in
            acknowledge(warning.id)
        })
        visibleAlert = alert
        presenter.present(alert, animated: true)
        // UIKit can refuse without calling a completion; do not acknowledge it.
        if presenter.presentedViewController !== alert {
            visibleAlert = nil
            retryWhenActive()
        }
    }

    private func retryWhenActive() {
        guard !pending.isEmpty, isForegroundActive(), !retryScheduled else { return }
        retryScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.retryScheduled = false
            self?.flush() // Rechecks foreground state; never presents in background.
        }
    }
}
