import UIKit

/// Table view cell styled as a dark card for displaying a single alarm in the list.
final class AlarmCell: UITableViewCell {

    static let reuseID = "AlarmCell"

    // MARK: - UI Elements

    private let cardView: UIView = {
        let view = UIView()
        view.backgroundColor = AppColors.surface
        view.layer.cornerRadius = AppRadius.md
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let timeLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.monospacedDigitSystemFont(ofSize: 52, weight: .medium)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let detailLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 13, weight: .regular)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let penaltyLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        label.textColor = AppColors.accentOrange
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    let toggleSwitch: UISwitch = {
        let sw = UISwitch()
        sw.onTintColor = AppColors.accentGreen
        sw.translatesAutoresizingMaskIntoConstraints = false
        return sw
    }()

    // MARK: - Callbacks

    /// Invoked when the user flips the toggle. Set by the controller in `cellForRowAt`.
    /// Capturing the alarm's id (not row index or `tag`) lets the controller resolve
    /// the right alarm even after deletion or reordering.
    var onToggle: ((Bool) -> Void)?

    // MARK: - Init

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
        // Wire the target once at cell creation so re-configuration in
        // `cellForRowAt` never accumulates duplicate handlers.
        toggleSwitch.addTarget(self, action: #selector(toggleSwitchChanged), for: .valueChanged)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupUI() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none

        contentView.addSubview(cardView)
        cardView.addSubview(timeLabel)
        cardView.addSubview(detailLabel)
        cardView.addSubview(penaltyLabel)
        cardView.addSubview(toggleSwitch)

        NSLayoutConstraint.activate([
            // Card with horizontal and vertical insets
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: AppSpacing.sm / 2),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: AppSpacing.lg),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -AppSpacing.lg),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -AppSpacing.sm / 2),

            // Toggle in top-right corner of card
            toggleSwitch.topAnchor.constraint(equalTo: cardView.topAnchor, constant: AppSpacing.lg),
            toggleSwitch.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -AppSpacing.lg),

            // Time label (large, top-left)
            timeLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: AppSpacing.md),
            timeLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: AppSpacing.lg),
            timeLabel.trailingAnchor.constraint(lessThanOrEqualTo: toggleSwitch.leadingAnchor, constant: -AppSpacing.sm),

            // Detail line: "Name - Days"
            detailLabel.topAnchor.constraint(equalTo: timeLabel.bottomAnchor, constant: AppSpacing.xs),
            detailLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: AppSpacing.lg),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: cardView.trailingAnchor, constant: -AppSpacing.lg),

            // Penalty line at the bottom
            penaltyLabel.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: AppSpacing.sm),
            penaltyLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: AppSpacing.lg),
            penaltyLabel.trailingAnchor.constraint(lessThanOrEqualTo: cardView.trailingAnchor, constant: -AppSpacing.lg),
            penaltyLabel.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -AppSpacing.md),
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        // The closure captures the previous row's identity — drop it so the
        // recycled cell never fires the wrong alarm before the next configure.
        onToggle = nil
    }

    // MARK: - Configure

    func configure(time: String, detail: String, penalty: String, enabled: Bool) {
        timeLabel.text = time
        detailLabel.text = detail
        penaltyLabel.text = penalty
        toggleSwitch.isOn = enabled
        setEnabledAppearance(enabled)
    }

    /// Updates the dim/full opacity of text labels to match enabled state.
    /// Called both during initial configuration and live from the toggle handler.
    func setEnabledAppearance(_ enabled: Bool) {
        let alpha: CGFloat = enabled ? 1.0 : 0.4
        timeLabel.alpha = alpha
        detailLabel.alpha = alpha
        penaltyLabel.alpha = alpha
    }

    @objc private func toggleSwitchChanged() {
        let isOn = toggleSwitch.isOn
        setEnabledAppearance(isOn)
        onToggle?(isOn)
    }
}
