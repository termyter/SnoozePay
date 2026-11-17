import UIKit

/// A quiet durable retry entry. It never owns alarm audio or a firing route.
final class AlarmFinishRecoveryPanel: UIStackView {
    var onRetry: ((AlarmOccurrenceFinishTicket) -> Void)?
    var onReload: (() -> Void)?
    private(set) var retryButtons: [UIButton] = []

    init() {
        super.init(frame: .zero)
        axis = .vertical
        spacing = AppSpacing.sp3
        isLayoutMarginsRelativeArrangement = true
        layoutMargins = UIEdgeInsets(top: AppSpacing.sp4, left: AppSpacing.sp4,
                                    bottom: AppSpacing.sp4, right: AppSpacing.sp4)
        backgroundColor = AppColors.bg1
        layer.cornerRadius = AppRadius.sm
        accessibilityIdentifier = "alarmFinishRecovery.panel"
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(entries: [AlarmOccurrenceRecoveryEntry], unavailable: Bool) {
        arrangedSubviews.forEach { removeArrangedSubview($0); $0.removeFromSuperview() }
        retryButtons = []
        addArrangedSubview(label(Localized.text("firing.finish.recovery.title"), emphasized: true))
        addArrangedSubview(label(Localized.text(unavailable
            ? "firing.finish.recovery.unavailable" : "firing.finish.recovery.message")))
        if unavailable {
            let button = makeButton(title: Localized.text("firing.finish.retry"))
            button.accessibilityIdentifier = "alarmFinishRecovery.reload"
            button.addAction(UIAction { [weak self] _ in self?.onReload?() }, for: .touchUpInside)
            retryButtons.append(button)
            addArrangedSubview(button)
        } else {
            for entry in entries {
                if let name = entry.alarmName, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    addArrangedSubview(label(name))
                }
                let button = makeButton(title: Localized.text("firing.finish.recovery.retry"))
                if let name = entry.alarmName, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    button.accessibilityLabel = Localized.text("firing.finish.recovery.retry") + ". " + name
                }
                button.accessibilityIdentifier = "alarmFinishRecovery.retry.\(entry.ticket.id.uuidString)"
                button.addAction(UIAction { [weak self] _ in self?.onRetry?(entry.ticket) }, for: .touchUpInside)
                retryButtons.append(button)
                addArrangedSubview(button)
            }
        }
    }

    private func label(_ text: String, emphasized: Bool = false) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = emphasized ? AppTypography.buttonSm : AppTypography.meta
        label.textColor = emphasized ? AppColors.fg1 : AppColors.fg2
        label.numberOfLines = 0
        return label
    }

    private func makeButton(title: String) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = AppTypography.buttonSm
        button.titleLabel?.numberOfLines = 0
        button.tintColor = AppColors.warn500
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        return button
    }
}
