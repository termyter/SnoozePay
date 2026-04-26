import UIKit

/// Table view cell styled as a dark card for displaying a single alarm in the list.
final class AlarmCell: UITableViewCell {

    static let reuseID = "AlarmCell"

    // MARK: - UI Elements

    private let cardView: UIView = {
        let view = UIView()
        view.backgroundColor = AppColors.surface
        view.layer.cornerRadius = AppRadius.md
        // Keep masksToBounds off so the drop shadow can render outside the rounded
        // bounds. Subviews are constrained inside the card via Auto Layout, so they
        // won't visually overflow even without clipping.
        view.layer.masksToBounds = false
        // Subtle drop shadow lifts the card off the background. In light mode this is
        // the primary visual separator since `secondarySystemBackground` (#FFFFFF) sits
        // on top of `systemGroupedBackground` (#F2F2F7) — only ~5% luminance delta.
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.06
        view.layer.shadowRadius = 8
        view.layer.shadowOffset = CGSize(width: 0, height: 2)
        // Hairline border reinforces the edge in light mode (UIColor.separator is
        // fully opaque grey in light, and very faint in dark — auto-adapts).
        view.layer.borderWidth = 0.5
        view.layer.borderColor = UIColor.separator.cgColor
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

        // CALayer's `cgColor` properties don't auto-resolve dynamic UIColors,
        // so refresh the border whenever the trait collection (light/dark) flips.
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (cell: AlarmCell, _) in
            cell.cardView.layer.borderColor = UIColor.separator.resolvedColor(
                with: cell.traitCollection
            ).cgColor
        }
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

    override func layoutSubviews() {
        super.layoutSubviews()
        // Pre-rasterize the shadow against the rounded card frame so scrolling
        // doesn't pay the per-pixel offscreen pass cost.
        cardView.layer.shadowPath = UIBezierPath(
            roundedRect: cardView.bounds,
            cornerRadius: AppRadius.md
        ).cgPath
        // Keep the border colour in sync with the current trait collection
        // (cgColor doesn't auto-update for dynamic UIColors).
        cardView.layer.borderColor = UIColor.separator.resolvedColor(
            with: traitCollection
        ).cgColor
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
