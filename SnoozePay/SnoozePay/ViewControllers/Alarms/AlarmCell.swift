import UIKit

/// Alarm row card — V2 design.
///
/// Visual recipe (matches `docs/design/v2-handoff/components/SPScreensV2.jsx`
/// L357-404):
/// ```
///  ┌──────────────────────────────────────────────────────────┐
///  │ БУДНИ · ПН–ПТ                              [ ●   ]      │
///  │                                                          │
///  │ 7:00                                                     │
///  │                                                          │
///  │ ┌──────┐  ┌──────┐  ┌─────────────┐                    │
///  │ │ 50 ₽ │  │  ×2  │  │  Soft Dawn  │                    │
///  │ └──────┘  └──────┘  └─────────────┘                    │
///  └──────────────────────────────────────────────────────────┘
/// ```
///
/// Three tonal states, all 20pt internal padding / 20pt corner radius:
/// - **enabled**:  `bg2` raised surface, `fg1` clock + `fg3` caps.
/// - **disabled**: `bg1` surface, `fg3` clock + `fg4` caps.
/// - **selected**: handled by `setHighlighted(_:)` press feedback.
///
/// The caps row uses an attributed string with `AppTypography.capsKerning`
/// so tracking stays in lock-step with the global caps recipe.
final class AlarmCell: UITableViewCell {

    static let reuseID = "AlarmCell"

    // MARK: - UI Elements

    private let cardView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = AppRadius.lg  // 20pt
        view.layer.masksToBounds = true
        view.layer.borderWidth = 1
        return view
    }()

    private let capsLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.85
        return label
    }()

    let toggleSwitch: SPSwitch = {
        let sw = SPSwitch()
        sw.translatesAutoresizingMaskIntoConstraints = false
        return sw
    }()

    private let clockLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        // 64pt mono light `clockLg` with tabular nums.
        label.font = AppTypography.clockLg.monospacedDigit()
        label.textColor = AppColors.fg1
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
        return label
    }()

    /// Horizontal stack of SPPills (price / multiplier / sound). Re-built on
    /// every `configure(...)` since the pill set is data-dependent and SPPill
    /// instances aren't designed for in-place mutation.
    private let pillsStack: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 6
        stack.distribution = .fill
        return stack
    }()

    // MARK: - Callbacks

    /// Invoked when the user flips the toggle. Set by the controller in `cellForRowAt`.
    var onToggle: ((Bool) -> Void)?

    // MARK: - Init

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
        toggleSwitch.addTarget(self, action: #selector(toggleSwitchChanged), for: .valueChanged)
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (cell: AlarmCell, _) in
                cell.refreshDynamicColors()
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @available(iOS, deprecated: 17.0, message: "Replaced by registerForTraitChanges; kept for iOS 15/16.")
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if #available(iOS 17.0, *) { return }
        refreshDynamicColors()
    }

    private func refreshDynamicColors() {
        // CALayer cgColor doesn't auto-resolve dynamic UIColors.
        cardView.layer.borderColor = AppColors.whiteOverlay08.cgColor
    }

    // MARK: - Setup

    private func setupUI() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none

        contentView.addSubview(cardView)
        cardView.addSubview(capsLabel)
        cardView.addSubview(toggleSwitch)
        cardView.addSubview(clockLabel)
        cardView.addSubview(pillsStack)

        let pad = AppSpacing.sp5 // 20pt
        // Outer card insets within the cell — horizontal screen inset, small
        // vertical breathing so consecutive cards have visible separation
        // without an explicit divider line. Bottom is half so the scroll
        // gap between cards lands at `AppSpacing.sp3` (12pt) per the spec.
        let outerH = AppSpacing.screenInset
        let outerV: CGFloat = 6

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: outerV),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: outerH),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -outerH),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -outerV),

            // Caps top-leading, switch top-trailing — aligned by centerY.
            capsLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: pad),
            capsLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: pad),
            capsLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: toggleSwitch.leadingAnchor,
                constant: -AppSpacing.sp3
            ),

            toggleSwitch.centerYAnchor.constraint(equalTo: capsLabel.centerYAnchor),
            toggleSwitch.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -pad),

            // Clock below the caps row.
            clockLabel.topAnchor.constraint(equalTo: capsLabel.bottomAnchor, constant: 4),
            clockLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: pad),
            clockLabel.trailingAnchor.constraint(lessThanOrEqualTo: cardView.trailingAnchor, constant: -pad),

            // Pill row at the bottom — 14pt gap below the clock.
            pillsStack.topAnchor.constraint(equalTo: clockLabel.bottomAnchor, constant: 14),
            pillsStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: pad),
            pillsStack.trailingAnchor.constraint(lessThanOrEqualTo: cardView.trailingAnchor, constant: -pad),
            pillsStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -pad)
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onToggle = nil
        // Pills are data-dependent — wipe them so reuse doesn't render the
        // previous alarm's pills for a frame before configure() re-fills.
        pillsStack.arrangedSubviews.forEach { view in
            pillsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    // MARK: - Configure

    /// Configure the row's content. Inputs:
    /// - `time`: pre-formatted "HH:mm".
    /// - `daysCaps`: caps string for the top-left ("БУДНИ · ПН–ПТ" /
    ///   "ВЫХОДНЫЕ" / "ПН, ВТ, СР").
    /// - `priceText`: e.g. "50 ₽".
    /// - `multiplier`: optional progressive-pain pill label ("×2" / "×4"
    ///   / etc.). `nil` hides the pill.
    /// - `soundName`: optional neutral pill — display name of the picked
    ///   sound. `nil` hides the pill.
    /// - `enabled`: drives the tonal switch between bg2 / bg1 surfaces.
    func configure(
        time: String,
        daysCaps: String,
        priceText: String,
        multiplier: String?,
        soundName: String?,
        enabled: Bool
    ) {
        clockLabel.text = time
        capsLabel.attributedText = NSAttributedString(
            string: daysCaps,
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: enabled ? AppColors.fg3 : AppColors.fg4
            ]
        )
        toggleSwitch.isOn = enabled
        applyEnabledTone(enabled)
        rebuildPills(price: priceText, multiplier: multiplier, soundName: soundName, enabled: enabled)
    }

    /// Legacy-style call site preserved for migration. Forwards to the
    /// V2 signature with empty pill set so callers that haven't been
    /// updated yet still compile. New code should use `configure(time:
    /// daysCaps: priceText: multiplier: soundName: enabled:)`.
    func configure(time: String, detail: String, penalty: String, enabled: Bool, theme: AlarmTheme) {
        _ = theme // theme strip retired in V2 layout.
        configure(
            time: time,
            daysCaps: detail.uppercased(),
            priceText: penalty,
            multiplier: nil,
            soundName: nil,
            enabled: enabled
        )
    }

    private func rebuildPills(price: String, multiplier: String?, soundName: String?, enabled: Bool) {
        pillsStack.arrangedSubviews.forEach { view in
            pillsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        // Price pill — warn-tone when enabled, neutral when disabled so a
        // dimmed row doesn't shout "50 ₽" at the user.
        let pricePill = SPPill(text: price, tone: enabled ? .warn : .neutral)
        pillsStack.addArrangedSubview(pricePill)

        if let multiplier = multiplier {
            let mult = SPPill(text: multiplier, tone: enabled ? .pain : .neutral)
            pillsStack.addArrangedSubview(mult)
        }
        if let soundName = soundName, !soundName.isEmpty {
            let sound = SPPill(text: soundName, tone: .neutral)
            pillsStack.addArrangedSubview(sound)
        }
        // Trailing spacer so pills don't stretch.
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        pillsStack.addArrangedSubview(spacer)
    }

    private func applyEnabledTone(_ enabled: Bool) {
        cardView.backgroundColor = enabled ? AppColors.bg2 : AppColors.bg1
        clockLabel.textColor = enabled ? AppColors.fg1 : AppColors.fg3
        cardView.layer.borderColor = AppColors.whiteOverlay08.cgColor
    }

    @objc private func toggleSwitchChanged() {
        let isOn = toggleSwitch.isOn
        applyEnabledTone(isOn)
        // Recolour the caps + pill set to track the new tone.
        if let attributed = capsLabel.attributedText?.string {
            capsLabel.attributedText = NSAttributedString(
                string: attributed,
                attributes: [
                    .font: AppTypography.caps,
                    .kern: AppTypography.capsKerning,
                    .foregroundColor: isOn ? AppColors.fg3 : AppColors.fg4
                ]
            )
        }
        onToggle?(isOn)
    }

    /// Press-feedback scale. Mirrors the design-system 0.97 scale used by
    /// SPButton / SPAmountPreset so cards pulse on the same delta as
    /// every other tappable surface.
    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        SPSupport.animatePress(cardView, pressed: highlighted)
    }
}
