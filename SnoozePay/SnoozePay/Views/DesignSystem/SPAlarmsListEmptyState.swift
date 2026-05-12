import UIKit

/// Empty-state column for the alarms list (V2 design).
///
/// Reference: `docs/design/v2-handoff/components/SPMore.jsx` L376-407.
///
/// Visual:
/// ```
///                ┌───────────┐
///                │   🔔      │   <- 96×96 warm-gradient rounded square
///                └───────────┘
///            ПОКА ПУСТО         <- caps fg3
///   Создайте первый будильник со
///   ставкой — он спишет деньги
///   за каждый снуз                <- body fg2
///
///        [   ＋ Создать первый   ]
/// ```
///
/// Hosted as an overlay over the table view in
/// `AlarmsListViewController` and toggled via `isHidden`.
final class SPAlarmsListEmptyState: UIView {

    // MARK: - Public API

    /// Triggered when the user taps "Создать первый".
    var onAddAlarmTap: (() -> Void)?

    // MARK: - Subviews

    /// 96×96 warm-gradient rounded square hosting the alarm icon.
    private let iconHost: SPGradientView = {
        let view = SPGradientView(
            colors: SPSupport.warnGradientColors,
            locations: SPSupport.warnGradientLocations
        )
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = AppRadius.xl  // 28pt
        view.layer.masksToBounds = true
        return view
    }()

    private let iconView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFit
        view.tintColor = AppColors.fgOnWarn
        let config = UIImage.SymbolConfiguration(pointSize: 44, weight: .semibold)
        view.image = UIImage(systemName: "alarm.fill", withConfiguration: config)
        return view
    }()

    private let capsLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.attributedText = NSAttributedString(
            string: "ПОКА ПУСТО",
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: AppColors.fg3
            ]
        )
        label.textAlignment = .center
        return label
    }()

    private let bodyLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Создайте первый будильник со ставкой — он спишет деньги за каждый снуз."
        label.font = AppTypography.body
        label.textColor = AppColors.fg2
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private let addButton: SPButton = {
        let button = SPButton(
            title: "Создать первый",
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

        addSubview(iconHost)
        iconHost.addSubview(iconView)

        let textStack = UIStackView(arrangedSubviews: [capsLabel, bodyLabel])
        textStack.axis = .vertical
        textStack.alignment = .center
        textStack.spacing = AppSpacing.sp2
        textStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textStack)
        addSubview(addButton)

        addButton.addTarget(self, action: #selector(addTapped), for: .touchUpInside)

        NSLayoutConstraint.activate([
            // Icon centered, 96×96.
            iconHost.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconHost.bottomAnchor.constraint(equalTo: textStack.topAnchor, constant: -AppSpacing.sp6),
            iconHost.widthAnchor.constraint(equalToConstant: 96),
            iconHost.heightAnchor.constraint(equalToConstant: 96),

            iconView.centerXAnchor.constraint(equalTo: iconHost.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconHost.centerYAnchor),

            // Text — centered group above the CTA.
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: AppSpacing.sp7),
            textStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -AppSpacing.sp7),

            // CTA — full-width below the text, anchored to a flexible gap so
            // the column reads "balanced" without forcing the button against
            // the safe-area bottom.
            addButton.topAnchor.constraint(equalTo: textStack.bottomAnchor, constant: AppSpacing.sp7),
            addButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: AppSpacing.screenInset),
            addButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -AppSpacing.screenInset)
        ])
    }

    // MARK: - Actions

    @objc private func addTapped() {
        onAddAlarmTap?()
    }
}
