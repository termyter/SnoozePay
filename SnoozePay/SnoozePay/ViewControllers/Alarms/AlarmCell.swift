import UIKit

/// Table view cell styled as a dark card for displaying a single alarm in the list.
final class AlarmCell: UITableViewCell {

    static let reuseID = "AlarmCell"

    // MARK: - UI Elements

    private let cardView: UIView = {
        let view = UIView()
        // Shared card recipe: rounded corners, hairline border, soft drop shadow.
        // See `UIView.applyCardStyle()` for the full rationale (light-mode
        // contrast). The `shadowRadius` is bumped slightly here (8pt) compared
        // to the default to keep the historical look of the alarm-row cards;
        // tweak via direct `layer` access after applying the helper.
        view.applyCardStyle()
        view.layer.shadowRadius = 8
        view.layer.shadowOffset = CGSize(width: 0, height: 2)
        view.clipsToBounds = false
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    /// Leading 6pt vertical strip painted with the alarm's theme gradient
    /// (or thumbnail for `.custom`) so the user can spot which theme each
    /// row uses without opening the editor (#151). Lives inside the card
    /// view so it inherits the card's clip + corner radius.
    private let themeStripContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.clipsToBounds = true
        return view
    }()

    private let themeStripImageView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.layer.cornerRadius = 3
        view.isHidden = true
        return view
    }()

    private var themeStripGradient: CAGradientLayer?

    private let timeLabel: UILabel = {
        let label = UILabel()
        // Brand clock face — 64pt JetBrainsMono Light per `tokens.css` `clockLg`.
        // 64pt at JBM Light easily exceeds the available width on a 393pt screen
        // for "23:58"-class strings, so allow auto-shrink down to 85% to keep
        // the row from clipping or wrapping.
        label.font = AppTypography.clockLg.monospacedDigit()
        label.textColor = AppColors.fg1
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.85
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let detailLabel: UILabel = {
        let label = UILabel()
        label.font = AppTypography.meta
        label.textColor = AppColors.fg3
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let penaltyLabel: UILabel = {
        // Warn-toned penalty caption. Using `caps` (12pt bold + 0.12em kerning
        // applied per-text in `configure`) and the brand `warn400` foreground
        // tone instead of the legacy `accentOrange` alias.
        let label = UILabel()
        label.font = AppTypography.caps
        label.textColor = AppColors.warn400
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    let toggleSwitch: UISwitch = {
        let sw = UISwitch()
        sw.onTintColor = AppColors.money500
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
            cell.cardView.layer.borderColor = AppColors.stroke1.resolvedColor(
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
        cardView.addSubview(themeStripContainer)
        themeStripContainer.addSubview(themeStripImageView)
        cardView.addSubview(timeLabel)
        cardView.addSubview(detailLabel)
        cardView.addSubview(penaltyLabel)
        cardView.addSubview(toggleSwitch)

        // 6pt theme strip pinned to the leading edge, shifted in 6pt from the
        // card edge so it doesn't sit flush against the rounded corner. The
        // strip's height fills the card minus 8pt top/bottom insets so it
        // reads as a deliberate accent rather than a clipped fill.
        let stripLeading = AppSpacing.sm
        let stripWidth: CGFloat = 6
        let timeLeading = stripLeading + stripWidth + AppSpacing.md // 8 + 6 + 12 = 26

        NSLayoutConstraint.activate([
            // Card with horizontal and vertical insets
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: AppSpacing.sm / 2),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: AppSpacing.lg),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -AppSpacing.lg),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -AppSpacing.sm / 2),

            // Theme strip — leading edge of the card, full height minus padding.
            themeStripContainer.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: stripLeading),
            themeStripContainer.topAnchor.constraint(equalTo: cardView.topAnchor, constant: AppSpacing.sm),
            themeStripContainer.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -AppSpacing.sm),
            themeStripContainer.widthAnchor.constraint(equalToConstant: stripWidth),

            themeStripImageView.topAnchor.constraint(equalTo: themeStripContainer.topAnchor),
            themeStripImageView.leadingAnchor.constraint(equalTo: themeStripContainer.leadingAnchor),
            themeStripImageView.trailingAnchor.constraint(equalTo: themeStripContainer.trailingAnchor),
            themeStripImageView.bottomAnchor.constraint(equalTo: themeStripContainer.bottomAnchor),

            // Toggle in top-right corner of card
            toggleSwitch.topAnchor.constraint(equalTo: cardView.topAnchor, constant: AppSpacing.lg),
            toggleSwitch.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -AppSpacing.lg),

            // Time label (large, top-left) — left-padded to leave room for the strip.
            timeLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: AppSpacing.md),
            timeLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: timeLeading),
            timeLabel.trailingAnchor.constraint(lessThanOrEqualTo: toggleSwitch.leadingAnchor, constant: -AppSpacing.sm),

            // Detail line: "Name - Days"
            detailLabel.topAnchor.constraint(equalTo: timeLabel.bottomAnchor, constant: AppSpacing.xs),
            detailLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: timeLeading),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: cardView.trailingAnchor, constant: -AppSpacing.lg),

            // Penalty line at the bottom
            penaltyLabel.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: AppSpacing.sm),
            penaltyLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: timeLeading),
            penaltyLabel.trailingAnchor.constraint(lessThanOrEqualTo: cardView.trailingAnchor, constant: -AppSpacing.lg),
            penaltyLabel.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -AppSpacing.md)
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        // The closure captures the previous row's identity — drop it so the
        // recycled cell never fires the wrong alarm before the next configure.
        onToggle = nil
        // Reset the theme strip so the next row's gradient doesn't briefly
        // show the previous row's colours before configure() reapplies.
        themeStripGradient?.removeFromSuperlayer()
        themeStripGradient = nil
        themeStripImageView.image = nil
        themeStripImageView.isHidden = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Pre-rasterize the shadow against the rounded card frame so scrolling
        // doesn't pay the per-pixel offscreen pass cost.
        cardView.layer.shadowPath = UIBezierPath(
            roundedRect: cardView.bounds,
            cornerRadius: AppRadius.sm
        ).cgPath
        // Keep the border colour in sync with the current trait collection
        // (cgColor doesn't auto-update for dynamic UIColors).
        cardView.layer.borderColor = AppColors.stroke1.resolvedColor(
            with: traitCollection
        ).cgColor

        // Round the strip and its gradient sublayer to a soft pill so it
        // reads as an accent rather than a hard rectangle.
        themeStripContainer.layer.cornerRadius = 3
        themeStripGradient?.frame = themeStripContainer.bounds
    }

    // MARK: - Configure

    func configure(time: String, detail: String, penalty: String, enabled: Bool, theme: AlarmTheme) {
        timeLabel.text = time
        detailLabel.text = detail
        // `caps` role pairs the 12pt bold font with +0.12em tracking per
        // `tokens.css`. Apply via attributedText so the kerning stays in lock-
        // step with the font role no matter where the string is set from.
        penaltyLabel.attributedText = NSAttributedString(
            string: penalty,
            attributes: [.kern: AppTypography.capsKerning]
        )
        toggleSwitch.isOn = enabled
        setEnabledAppearance(enabled)
        applyTheme(theme)
    }

    /// Paint the leading 6pt strip with the alarm's theme. Built-in themes
    /// install a vertical gradient layer; `.custom` swaps to the picked
    /// thumbnail image, falling back to the Dawn gradient when the file is
    /// gone (Caches purge).
    private func applyTheme(_ theme: AlarmTheme) {
        themeStripGradient?.removeFromSuperlayer()
        themeStripGradient = nil
        themeStripImageView.image = nil
        themeStripImageView.isHidden = true

        if case .custom(let url) = theme, let image = AlarmThemeImageStore.loadImage(at: url) {
            themeStripImageView.image = image
            themeStripImageView.isHidden = false
            return
        }

        let resolvedTheme: AlarmTheme = {
            if case .custom = theme { return .dawn }
            return theme
        }()
        guard let colors = AlarmThemeRendering.gradientColors(for: resolvedTheme) else { return }
        let gradient = CAGradientLayer()
        gradient.colors = colors
        gradient.locations = AlarmThemeRendering.gradientLocations(for: resolvedTheme)
        gradient.startPoint = CGPoint(x: 0.5, y: 0.0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1.0)
        gradient.frame = themeStripContainer.bounds
        gradient.cornerRadius = 3
        themeStripContainer.layer.insertSublayer(gradient, at: 0)
        themeStripGradient = gradient
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
