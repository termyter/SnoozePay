import UIKit

/// Alarm row card — V2 design.
///
/// Visual recipe (matches `docs/design/v2-handoff/components/SPScreensV2.jsx`
/// L357-404):
/// ```
///  ┌──────────────────────────────────────────────────────────┐
///  │ БУДНИ · ПН–ПТ                              [ ●   ]      │
///  │                                                          │
///  │ 07:00                                                    │
///  │                                                          │
///  │ ┌──────┐  ┌──────┐  ┌─────────────┐                    │
///  │ │ 50 ₽ │  │  ×2  │  │  Soft Dawn  │                    │
///  │ └──────┘  └──────┘  └─────────────┘                    │
///  └──────────────────────────────────────────────────────────┘
/// ```
///
/// Three tonal states, all 20pt internal padding / 20pt corner radius. The
/// card chrome follows the `SPCard` recipe (SPScreensV2.jsx L404/L421) so it
/// reads as the same primitive as every other surface — `shadow-1`/`shadow-2`
/// plus the documented light-mode hairline a11y deviation, instead of the old
/// flat 1pt border with no shadow (#280):
/// - **enabled**:  `SPCard(tone: .raised)` — `bgRaised` surface, `fg1` clock
///   + `fg3` caps.
/// - **disabled**: `SPCard(tone: .surface)` — `bg1` surface, `fg3` clock + `fg4` caps.
/// - **selected**: handled by `setHighlighted(_:)` press feedback.
///
/// The caps row uses an attributed string with `AppTypography.capsKerning`
/// so tracking stays in lock-step with the global caps recipe.
final class AlarmCell: UITableViewCell {

    static let reuseID = "AlarmCell"

    // MARK: - UI Elements

    /// Card surface. Applies the `SPCard` `.raised`/`.surface` recipe inline
    /// (`bgRaised`/`bg1` fill + shadow-2 / shadow-1 + light-mode hairline)
    /// rather than embedding an `SPCard` — that primitive's tone is immutable
    /// at init and the cell flips tone per enabled state. `masksToBounds` stays `false` so the shadow can
    /// render; the rounded corners only clip the background/border on the
    /// layer, and the cell's subviews never extend past the card edge.
    private let cardView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = AppRadius.lg  // 20pt
        view.layer.masksToBounds = false
        return view
    }()

    /// Title/days caps row. Long alarm names WRAP onto new lines and are
    /// never truncated or shrunk — the card grows in height and the clock
    /// + pill rows slide down (`AlarmCardWrapDemo` in SPScreensV2.jsx,
    /// #232). The ≈26-char single-line capacity is a fact of the layout,
    /// not an input limit.
    private let capsLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        // Required vertical resistance so the multi-line height always
        // wins over the card's compressed fitting pass — without it the
        // self-sizing cell could clip the second line instead of growing.
        label.setContentCompressionResistancePriority(.required, for: .vertical)
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

    // MARK: - State

    /// Tracks the last applied enabled tone so theme-flip / layout passes can
    /// re-resolve the (CALayer cgColor / shadow) recipe without the controller
    /// re-calling `configure`.
    private var isEnabledTone = true

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
        // CALayer cgColor + shadow recipe don't auto-resolve dynamic UIColors,
        // so re-install the whole card chrome on a theme flip.
        applyCardChrome(enabled: isEnabledTone)
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

            // Caps top-leading, switch top-trailing. The caps label gets a
            // fully-determined width (equality, not ≤) so UILabel computes
            // its wrapped multi-line height on its own — long names break
            // onto new lines instead of truncating (#232).
            capsLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: pad),
            capsLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: pad),
            capsLabel.trailingAnchor.constraint(
                equalTo: toggleSwitch.leadingAnchor,
                constant: -AppSpacing.sp3
            ),

            // The switch stays anchored to the FIRST caps line (its centre
            // sits where a single-line caps row's centre would be) so a
            // wrapped title doesn't drag the toggle down the card —
            // mirrors the demo's `alignItems: flex-start`.
            toggleSwitch.centerYAnchor.constraint(
                equalTo: cardView.topAnchor,
                constant: pad + AppTypography.caps.lineHeight / 2
            ),
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

        // Accessibility: VoiceOver would otherwise read the card's labels as
        // disconnected fragments ("07:00", "50 ₽", "×2"). Make the cell an
        // a11y container exposing exactly two elements — the card (a composed
        // summary label, updated in `configure`) and the toggle (a UISwitch,
        // which carries native on/off value + activation for free).
        isAccessibilityElement = false
        accessibilityElements = [cardView, toggleSwitch]
        cardView.isAccessibilityElement = true
        cardView.accessibilityTraits = .summaryElement
        toggleSwitch.accessibilityLabel = Localized.text("alarms.cell.toggle_accessibility")
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
        // Reset card chrome to a known (enabled) state. `applyCardChrome` only
        // *adds* the ambient `shadow-1` sublayer in its disabled branch, and
        // `layoutSubviews` re-installs it whenever `isEnabledTone` is false —
        // so a recycled cell whose previous alarm was disabled would paint the
        // stale ambient shadow / disabled tone for one layout pass before the
        // controller re-calls `configure`. Drop the ambient layer and reset the
        // tracked tone so the cell starts every reuse from the enabled recipe.
        cardView.layer.sublayers?
            .first { $0.name == AppShadow.ambientShadow1LayerName }?
            .removeFromSuperlayer()
        isEnabledTone = true
    }

    // MARK: - Configure

    /// Configure the row's content. Inputs:
    /// - `time`: pre-formatted clock string, e.g. "7:30" (the list uses the
    ///   unpadded `H:mm` form — see `AlarmsListViewModel.timeFormatter`).
    /// - `daysCaps`: caps string for the top-left («БУДНИ · ПН–ПТ» /
    ///   «ВЫХОДНЫЕ» / «ПН, ВТ, СР»).
    /// - `priceText`: e.g. "50 ₽".
    /// - `multiplier`: optional progressive-pain pill label ("×2" / "×4"
    ///   / etc.). `nil` hides the pill.
    /// - `soundName`: optional neutral pill — display name of the picked
    ///   sound. `nil` hides the pill.
    /// - `enabled`: drives the tonal switch between the raised and the base
    ///   surface.
    func configure(
        time: String,
        daysCaps: String,
        priceText: String,
        multiplier: String?,
        soundName: String?,
        enabled: Bool
    ) {
        // −0.04em clock tracking per SPScreensV2.jsx L408 (`letterSpacing:
        // -.04em`). The colour is applied separately by `applyEnabledTone`, so
        // omit `.foregroundColor` here and let the label's `textColor` win.
        clockLabel.attributedText = NSAttributedString(
            string: time,
            attributes: [
                .font: clockLabel.font as Any,
                .kern: AppTypography.clockLgKerning
            ]
        )
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

        // Compose the VoiceOver summary from the same fields and refresh the
        // toggle's value so the row reads as one coherent control pair.
        cardView.accessibilityLabel = Self.accessibilityLabel(
            time: time,
            daysCaps: daysCaps,
            priceText: priceText,
            multiplier: multiplier,
            soundName: soundName
        )
        toggleSwitch.accessibilityValue = Localized.text(
            enabled ? "alarms.cell.toggle_on" : "alarms.cell.toggle_off"
        )
    }

    /// Build the composed VoiceOver label for a card from its display fields,
    /// e.g. «Будильник 07:00, будни Пн–Пт, 50 ₽, ×2, Soft Dawn». Pure so it
    /// can be unit-tested without instantiating a cell. `daysCaps` arrives
    /// upper-cased for the visual caps row; VoiceOver reads sentence-case more
    /// naturally, so it's lowered with a capital first letter.
    static func accessibilityLabel(
        time: String,
        daysCaps: String,
        priceText: String,
        multiplier: String?,
        soundName: String?
    ) -> String {
        var parts: [String] = [Localized.format("alarms.cell.accessibility", time)]

        let days = sentenceCased(daysCaps)
        if !days.isEmpty { parts.append(days) }

        let price = priceText.trimmingCharacters(in: .whitespaces)
        if !price.isEmpty { parts.append(price) }

        if let multiplier = multiplier?.trimmingCharacters(in: .whitespaces), !multiplier.isEmpty {
            parts.append(multiplier)
        }
        if let soundName = soundName?.trimmingCharacters(in: .whitespaces), !soundName.isEmpty {
            parts.append(soundName)
        }
        return parts.joined(separator: ", ")
    }

    /// Lower-case a caps string and re-capitalise its first letter so VoiceOver
    /// reads «Будни · Пн–Пт» instead of spelling out the all-caps form.
    private static func sentenceCased(_ caps: String) -> String {
        let trimmed = caps.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "" }
        return first.uppercased() + trimmed.dropFirst().lowercased()
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
        // Enabled cards carry their 12px pill icons; disabled cards drop the
        // icons entirely so a dimmed row reads quieter (SPScreensV2.jsx
        // L414-418 vs L431-434, #280).
        // Price pill — warn-tone when enabled (leading ₽-coin), neutral +
        // icon-less when disabled.
        let pricePill = SPPill(
            text: price,
            tone: enabled ? .warn : .neutral,
            icon: enabled ? SPIcons.rubleCoin(size: 12) : nil
        )
        pillsStack.addArrangedSubview(pricePill)

        if let multiplier = multiplier {
            // Progressive multiplier — trend-up polyline (icon only when
            // enabled).
            let mult = SPPill(
                text: multiplier,
                tone: enabled ? .pain : .neutral,
                icon: enabled ? SPIcons.trendUp(size: 12) : nil
            )
            pillsStack.addArrangedSubview(mult)
        }
        if let soundName = soundName, !soundName.isEmpty {
            // Sound pill — neutral tone; the 12px speaker glyph appears only
            // on enabled cards (SPScreensV2.jsx L417, #280).
            let sound = SPPill(
                text: soundName,
                tone: .neutral,
                icon: enabled ? SPIcons.sound(size: 12) : nil
            )
            pillsStack.addArrangedSubview(sound)
        }
        // Trailing spacer so pills don't stretch.
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        pillsStack.addArrangedSubview(spacer)
    }

    private func applyEnabledTone(_ enabled: Bool) {
        isEnabledTone = enabled
        clockLabel.textColor = enabled ? AppColors.fg1 : AppColors.fg3
        applyCardChrome(enabled: enabled)
    }

    /// Install the `SPCard` chrome for the given tone: an enabled card uses the
    /// `.raised` recipe (`bgRaised` + `shadow-2`), a disabled card the
    /// `.surface` recipe (`bg1` + `shadow-1`). In light mode both add a 1pt
    /// hairline — the documented a11y deviation from `SPCard` (near-white
    /// surfaces need a stroke to read as a card). Dark mode relies on the
    /// shadow alone, no border, per the design (SPScreensV2.jsx L404/L421).
    ///
    /// The fill is `AppColors.bgRaised`, not the raw `bg2` this used to
    /// hardcode: `bg2` is a step *up* the ramp in dark but a step *down* in
    /// light, so the literal pair made the switched-OFF alarm the brightest
    /// card on a light list while the enabled ones went grey (#543). In light
    /// both states now share the white `bg1` fill, and the shadow pair this
    /// method already applied — shadow-2 vs shadow-1 — is what separates them.
    private func applyCardChrome(enabled: Bool) {
        cardView.backgroundColor = enabled ? AppColors.bgRaised : AppColors.bg1

        let trait = traitCollection
        let isLight = trait.userInterfaceStyle != .dark

        // Shadow recipe.
        let shadow = enabled ? AppShadow.shadow2(for: trait) : AppShadow.shadow1(for: trait)
        shadow.apply(to: cardView.layer)
        // The disabled (`shadow-1`) tone carries a narrow ambient stop on light
        // surfaces; the enabled (`shadow-2`) tone is a single stop, so clear
        // any stale ambient layer when switching tones.
        if enabled {
            cardView.layer.sublayers?
                .first { $0.name == AppShadow.ambientShadow1LayerName }?
                .removeFromSuperlayer()
        } else {
            AppShadow.installAmbientShadow1Layer(
                on: cardView.layer,
                cornerRadius: AppRadius.lg,
                trait: trait
            )
        }

        // Light-mode hairline a11y deviation.
        if isLight {
            let scale = trait.displayScale > 0 ? trait.displayScale : 1
            cardView.layer.borderWidth = 1.0 / scale
            cardView.layer.borderColor = AppColors.stroke1.resolvedColor(with: trait).cgColor
        } else {
            cardView.layer.borderWidth = 0
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Pre-rasterise the shadow against the rounded path + keep the ambient
        // layer frame in sync with the card bounds.
        cardView.layer.shadowPath = UIBezierPath(
            roundedRect: cardView.bounds,
            cornerRadius: AppRadius.lg
        ).cgPath
        if !isEnabledTone {
            AppShadow.installAmbientShadow1Layer(
                on: cardView.layer,
                cornerRadius: AppRadius.lg,
                trait: traitCollection
            )
        }
    }

    @objc private func toggleSwitchChanged() {
        let isOn = toggleSwitch.isOn
        applyEnabledTone(isOn)
        toggleSwitch.accessibilityValue = Localized.text(
            isOn ? "alarms.cell.toggle_on" : "alarms.cell.toggle_off"
        )
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
