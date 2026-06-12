import UIKit

/// Reusable icon + title row for the Settings table (finance, sound,
/// info, contact rows). Replaces the previous `makeIconRow` factory that built
/// `UITableViewCell(style:reuseIdentifier: nil)` on every `cellForRowAt:` —
/// nil-identifier cells are never recycled, so each reload leaked a fresh
/// cell hierarchy (#203).
///
/// V3 (#283) drops the iOS-style 30×30 colored chip in favour of a bare
/// tinted glyph per the design (`SPMore4.jsx` `IconCoin/IconClock/…` —
/// `size={20}` with a `--sp-*` tint, no container fill). The cell can also
/// host a trailing `SPSwitch` (Critical Alerts / vibration) and renders a
/// chevron via the standard `.disclosureIndicator` accessory.
///
/// `configure` resets every mutable bit of state, so no `prepareForReuse`
/// override is needed: a recycled cell is always fully re-specified before
/// it re-enters the viewport.
final class SettingsIconRowCell: UITableViewCell {

    static let reuseID = "SettingsIconRowCell"

    // MARK: - UI

    /// Bare tinted glyph (~20pt) — no chip container. `tintColor` is set per
    /// row in `configure`.
    private let iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .center
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = AppTypography.bodyLg
        label.textColor = AppColors.fg1
        label.numberOfLines = 1
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = AppTypography.meta
        label.textColor = AppColors.fg3
        label.numberOfLines = 0
        label.isHidden = true
        return label
    }()

    /// Right-aligned value (balance, snooze duration, "80%" etc.). Hidden
    /// unless configured.
    private let trailingLabel: UILabel = {
        let label = UILabel()
        label.font = AppTypography.meta
        label.isHidden = true
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }()

    /// Optional trailing toggle (Critical Alerts / vibration).
    private let trailingSwitch: SPSwitch = {
        let toggle = SPSwitch()
        toggle.isHidden = true
        toggle.translatesAutoresizingMaskIntoConstraints = false
        toggle.setContentHuggingPriority(.required, for: .horizontal)
        return toggle
    }()

    /// Forwarded on each `valueChanged` from `trailingSwitch`. Reset on
    /// reuse so a recycled cell can't fire a stale owner's handler.
    private var onSwitchChange: ((Bool) -> Void)?

    // MARK: - Init

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupUI() {
        backgroundColor = .secondarySystemBackground

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 2

        let mainStack = UIStackView(arrangedSubviews: [
            iconImageView, textStack, trailingLabel, trailingSwitch
        ])
        mainStack.axis = .horizontal
        mainStack.spacing = AppSpacing.md
        mainStack.alignment = .center
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(mainStack)

        trailingSwitch.addTarget(self, action: #selector(switchChanged), for: .valueChanged)

        NSLayoutConstraint.activate([
            // Fixed 24pt box so titles align across rows regardless of the
            // symbol's intrinsic width (the glyph renders ~20pt centred).
            iconImageView.widthAnchor.constraint(equalToConstant: 24),
            iconImageView.heightAnchor.constraint(equalToConstant: 24),

            mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: AppSpacing.lg),
            mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -AppSpacing.lg),
            mainStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: AppSpacing.sm),
            mainStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -AppSpacing.sm)
        ])
    }

    // MARK: - Configure

    /// Fully re-specifies the row. Every property is written unconditionally
    /// so state from a previous tenant of this cell can't survive recycling.
    func configure(
        systemName: String,
        iconColor: UIColor,
        title: String,
        subtitle: String? = nil,
        trailingText: String? = nil,
        trailingColor: UIColor = AppColors.fg3,
        accessory: UITableViewCell.AccessoryType = .none,
        selectionStyle: UITableViewCell.SelectionStyle = .default
    ) {
        iconImageView.image = UIImage(systemName: systemName)?.withConfiguration(
            UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        )
        iconImageView.tintColor = iconColor

        titleLabel.text = title
        titleLabel.textColor = AppColors.fg1

        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle == nil

        trailingLabel.text = trailingText
        trailingLabel.textColor = trailingColor
        trailingLabel.isHidden = trailingText == nil

        trailingSwitch.isHidden = true
        onSwitchChange = nil

        accessoryType = accessory
        self.selectionStyle = selectionStyle
    }

    /// Switch-row variant (Critical Alerts / vibration). When `enabled` is
    /// `false` the toggle renders greyed-out and non-interactive — used for the
    /// Critical Alerts row whose entitlement isn't granted (no-touch / PM).
    func configureSwitch(
        systemName: String,
        iconColor: UIColor,
        title: String,
        subtitle: String? = nil,
        isOn: Bool,
        enabled: Bool = true,
        onChange: @escaping (Bool) -> Void
    ) {
        configure(
            systemName: systemName,
            iconColor: iconColor,
            title: title,
            subtitle: subtitle,
            accessory: .none,
            selectionStyle: .none
        )
        // Dim the title when the control is disabled so the row reads as
        // "unavailable" rather than "off".
        titleLabel.textColor = enabled ? AppColors.fg1 : AppColors.fg3
        trailingSwitch.isHidden = false
        trailingSwitch.isOn = isOn
        trailingSwitch.isEnabled = enabled
        trailingSwitch.alpha = enabled ? 1.0 : 0.5
        onSwitchChange = onChange
    }

    // MARK: - Actions

    @objc private func switchChanged() {
        onSwitchChange?(trailingSwitch.isOn)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onSwitchChange = nil
        trailingSwitch.isHidden = true
        trailingSwitch.isEnabled = true
        trailingSwitch.alpha = 1.0
    }
}
