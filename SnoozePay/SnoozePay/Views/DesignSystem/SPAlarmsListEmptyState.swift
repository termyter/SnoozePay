import UIKit

/// Empty-state column for the alarms list.
///
/// Visual:
///   ┌─────────────────────────────┐
///   │             🔕              │
///   │     Нет будильников         │
///   │ Создайте первый, чтобы …    │
///   │   [+ Добавить будильник]    │
///   └─────────────────────────────┘
///
/// Hosted as an overlay over the table view in
/// `AlarmsListViewController` and toggled via `isHidden`. Uses
/// `AppTypography` + `SPButton(.money, .lg)` so it stays visually
/// consistent with the rest of the design system.
final class SPAlarmsListEmptyState: UIView {

    // MARK: - Public API

    /// Triggered when the user taps "Добавить будильник".
    var onAddAlarmTap: (() -> Void)?

    // MARK: - Subviews

    private let iconView: UIImageView = {
        let configuration = UIImage.SymbolConfiguration(pointSize: 64, weight: .regular)
        let view = UIImageView(image: UIImage(systemName: "bell.slash", withConfiguration: configuration))
        view.tintColor = AppColors.fg3
        view.contentMode = .scaleAspectFit
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Нет будильников"
        label.font = AppTypography.h2
        label.textColor = AppColors.fg1
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Создайте первый, чтобы начать"
        label.font = AppTypography.body
        label.textColor = AppColors.fg3
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let addButton: SPButton = {
        let button = SPButton(
            title: "Добавить будильник",
            variant: .money,
            size: .lg,
            icon: UIImage(systemName: "plus")
        )
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Configuration

    private func configure() {
        backgroundColor = .clear

        let stack = UIStackView(arrangedSubviews: [
            iconView, titleLabel, subtitleLabel, addButton
        ])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = AppSpacing.sp3
        stack.setCustomSpacing(AppSpacing.sp4, after: iconView)
        stack.setCustomSpacing(AppSpacing.sp5, after: subtitleLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: AppSpacing.sp6),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -AppSpacing.sp6),

            iconView.widthAnchor.constraint(equalToConstant: 80),
            iconView.heightAnchor.constraint(equalToConstant: 80)
        ])

        addButton.addTarget(self, action: #selector(addTapped), for: .touchUpInside)
    }

    // MARK: - Actions

    @objc private func addTapped() {
        onAddAlarmTap?()
    }
}
