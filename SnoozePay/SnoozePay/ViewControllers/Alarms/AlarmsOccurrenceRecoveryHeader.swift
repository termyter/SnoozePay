import UIKit
import os

/// Composes durable retry actions with the existing list header. No pending
/// state leaves the list's ordinary streak header and empty state unchanged.
final class AlarmsOccurrenceRecoveryHeader {
    let header = UIStackView()
    private let panel = AlarmFinishRecoveryPanel()
    private let recovery: AlarmOccurrenceRecovering
    private weak var host: UIViewController?
    private let onChange: () -> Void
    private var entries: [AlarmOccurrenceRecoveryEntry] = []
    private var unavailable = false

    init(recovery: AlarmOccurrenceRecovering, host: UIViewController, onChange: @escaping () -> Void) {
        self.recovery = recovery
        self.host = host
        self.onChange = onChange
        panel.onRetry = { [weak self] ticket in self?.retry(ticket) }
        panel.onReload = { [weak self] in self?.onChange() }
        header.axis = .vertical
        header.spacing = AppSpacing.sp3
    }

    func refresh() {
        do {
            entries = try recovery.pendingFinishes()
            unavailable = false
        } catch {
            entries = []
            unavailable = true
            AppLogger.emit(.ui, .error, "Pending occurrence discovery unavailable")
        }
        if unavailable || !entries.isEmpty { panel.configure(entries: entries, unavailable: unavailable) }
    }

    func compose(on table: UITableView, emptyState: UIView, hasAlarms: Bool, width: CGFloat) {
        let hasRecovery = unavailable || !entries.isEmpty
        emptyState.isHidden = hasRecovery || hasAlarms
        table.isHidden = !hasRecovery && !hasAlarms
        guard hasRecovery else {
            header.arrangedSubviews.forEach { header.removeArrangedSubview($0); $0.removeFromSuperview() }
            return
        }
        let existing = table.tableHeaderView
        header.arrangedSubviews.forEach { header.removeArrangedSubview($0); $0.removeFromSuperview() }
        header.addArrangedSubview(panel)
        if let existing, existing !== header {
            existing.translatesAutoresizingMaskIntoConstraints = false
            header.addArrangedSubview(existing)
        }
        header.translatesAutoresizingMaskIntoConstraints = true
        table.tableHeaderView = header
        sizeHeader(on: table, width: width)
    }

    func sizeHeader(on table: UITableView, width fallbackWidth: CGFloat) {
        let width = table.bounds.width > 0 ? table.bounds.width : fallbackWidth
        guard width > 0 else { return }
        let size = header.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel
        )
        let frame = CGRect(x: 0, y: 0, width: width, height: size.height)
        if header.frame != frame {
            header.frame = frame
            table.tableHeaderView = header
        }
    }

    private func retry(_ ticket: AlarmOccurrenceFinishTicket) {
        guard let host else { return }
        AlarmOccurrenceRecoveryAlerts.perform(ticket, on: host, recovery: recovery, onChange: onChange)
    }
}
