import UIKit

/// Empty-state column shown on the statistics screen when the selected
/// period has no transactions. Mirrors the alarms-list empty state in
/// shape (icon + heading + body + primary CTA) but uses a chart icon and
/// "Создать будильник" copy so the user lands on the alarm-creation flow
/// rather than the top-up flow.
///
/// Hosted by `StatisticsViewController`; the controller listens to
/// `onCreateAlarmTap` to push `CreateAlarmViewController(alarm: nil)`.
final class StatisticsEmptyStateView: UIView {

    // MARK: - Public API

    /// Triggered when the user taps "Создать будильник".
    var onCreateAlarmTap: (() -> Void)?

    // MARK: - Subviews

    private let iconView: UIImageView = {
        let configuration = UIImage.SymbolConfiguration(pointSize: 64, weight: .regular)
        let view = UIImageView(image: UIImage(systemName: "chart.bar.xaxis", withConfiguration: configuration))
        view.tintColor = AppColors.fg3
        view.contentMode = .scaleAspectFit
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Пока нет данных"
        label.font = AppTypography.h3
        label.textColor = AppColors.fg1
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let bodyLabel: UILabel = {
        let label = UILabel()
        label.text = "Создайте будильник, чтобы отслеживать серии"
        label.font = AppTypography.body
        label.textColor = AppColors.fg3
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let createButton: SPButton = {
        let button = SPButton(
            title: "Создать будильник",
            variant: .money,
            size: .lg,
            icon: UIImage(systemName: "plus"),
            fullWidth: true
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

        let stack = UIStackView(arrangedSubviews: [iconView, titleLabel, bodyLabel, createButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = AppSpacing.sp3
        stack.setCustomSpacing(AppSpacing.sp4, after: iconView)
        stack.setCustomSpacing(AppSpacing.sp5, after: bodyLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 80),
            iconView.heightAnchor.constraint(equalToConstant: 80),

            stack.topAnchor.constraint(equalTo: topAnchor, constant: AppSpacing.sp7),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -AppSpacing.sp5),

            createButton.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: AppSpacing.sp4),
            createButton.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -AppSpacing.sp4)
        ])

        createButton.addTarget(self, action: #selector(createTapped), for: .touchUpInside)
    }

    @objc private func createTapped() {
        onCreateAlarmTap?()
    }
}
