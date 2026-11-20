import UIKit

/// V2 «Прогрессивный режим» card (#231, `SPMore2.jsx` AlarmEdit).
///
/// A single self-contained card: leading flame icon + h4 title, rationale
/// subtitle, the doubling chain `50 → 100 → 200 → 400 ₽` (coloured when
/// armed, muted when not — #688) and a trailing `SPSwitch`. When armed, the card surface
/// flips to the pain-tinted gradient + pain hairline so the row reads as
/// "this will hurt" at a glance.
///
/// The cell owns its `backgroundView` (the host controller's generic
/// `styleAsCardRow` recipe is skipped for this cell) because the pain tint
/// must survive both the toggle flip and table re-measure passes.
final class ProgressiveScaleCell: UITableViewCell {

    static let reuseID = "ProgressiveScaleCell"

    // MARK: - UI

    private let surface = ProgressiveCardSurface()

    private let iconView: UIImageView = {
        let image = UIImage(systemName: "flame.fill")?.withConfiguration(
            UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        )
        let view = UIImageView(image: image)
        view.tintColor = AppColors.fg3
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = Localized.text("create_alarm.progressive.title")
        label.font = AppTypography.scaled(AppTypography.h4, as: .headline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = AppColors.fg1
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.text = Localized.text("create_alarm.progressive.subtitle")
        label.font = AppTypography.scaledMeta
        label.adjustsFontForContentSizeCategory = true
        label.textColor = AppColors.fg3
        label.numberOfLines = 0
        return label
    }()

    /// `50 → 100 → 200 → 400 ₽` — mono digits, warn-tinted start, pain-tinted
    /// tail, final value rendered through `MoneyFormatter`. One shrinking line
    /// up to `.large`; from XL it wraps at the arrows (`applyLayout`).
    private let chainLabel: UILabel = {
        let label = UILabel()
        label.minimumScaleFactor = 0.7
        return label
    }()

    /// The canon's `flex: 1` column — title row, subtitle and chain sit beside
    /// the switch, not under it,
    /// `docs/design/snoozepay-2026-04-27/project/components/SPMore2.jsx:259-262` contains "Прогрессивный режим".
    ///
    /// `.fill`, not `.leading`: under `.leading` every row kept its intrinsic
    /// width, which for a `numberOfLines = 0` label is its SINGLE-LINE width.
    /// The column then had no definite width of its own, so where the subtitle
    /// broke was decided by compression-resistance tie-breaks rather than by
    /// the space available — it wrapped at "в 2 / раза" with half the card
    /// still empty to its right (#638).
    private let contentStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let toggle = SPSwitch()

    /// Flame + title: side by side, or from XL the flame above the title, so
    /// the title has the column's full width (`applyLayout`).
    private let headerRow = UIStackView()

    /// What `configure` last rendered, kept so the switch can repaint the
    /// chain in place without the host re-`configure`-ing the cell.
    private var chain: [Double] = []
    private var currency: Currency = .rub
    private var accessibilityChain = ""

    /// Up to `.large`: the switch beside the column, as before.
    private var switchBeside: [NSLayoutConstraint] = []
    /// From XL: the column takes the card's width and the switch drops under
    /// it — at 2× «Прогрессивный» alone is wider than the column (#1111).
    private var switchUnder: [NSLayoutConstraint] = []

    // MARK: - Callbacks

    var onToggled: ((Bool) -> Void)?

    // MARK: - Init

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
        toggle.addTarget(self, action: #selector(toggled), for: .valueChanged)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (cell: ProgressiveScaleCell, _) in
            cell.applyLayout()
            cell.applyArmedAppearance(cell.toggle.isOn)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        backgroundColor = .clear
        backgroundView = surface
        selectionStyle = .none

        headerRow.addArrangedSubview(iconView)
        headerRow.addArrangedSubview(titleLabel)
        headerRow.spacing = AppSpacing.sp2

        contentStack.addArrangedSubview(headerRow)
        contentStack.addArrangedSubview(subtitleLabel)
        contentStack.addArrangedSubview(chainLabel)
        contentStack.setCustomSpacing(6, after: headerRow)
        contentStack.setCustomSpacing(AppSpacing.sp3, after: subtitleLabel)

        toggle.translatesAutoresizingMaskIntoConstraints = false
        // VoiceOver otherwise reads the brand `SPSwitch` as the generic
        // «Переключатель». Give it the row's title so the control is
        // self-describing, mirroring AlarmCell's pattern (#425).
        toggle.accessibilityLabel = titleLabel.text

        contentView.addSubview(contentStack)
        contentView.addSubview(toggle)

        // A self-sized row still gets ~1pt of rounding slack, and on main the
        // header row has always been the one to take it (measured: the
        // subtitle starts 30.33pt below the column's top). The text rows hug
        // one step harder, so that is a rule instead of a hugging tie.
        subtitleLabel.setContentHuggingPriority(.defaultLow + 1, for: .vertical)
        chainLabel.setContentHuggingPriority(.defaultLow + 1, for: .vertical)

        // Card padding 20pt on all sides (#231 `padding=20` rule); the switch
        // is top-aligned with the header row per the artboard's
        // `alignItems: flex-start`.
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),

            contentStack.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: AppSpacing.cardHorizontalPadding
            ),
            contentStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: AppSpacing.sp5)
        ])
        let padding = AppSpacing.cardHorizontalPadding
        switchBeside = [
            contentStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -AppSpacing.sp5),
            // `equalTo`, not `lessThanOrEqualTo`: the column has to CLAIM the
            // width the switch leaves it, which is what `flex: 1` does in the
            // canon. Merely capping it left the width indefinite (#638).
            contentStack.trailingAnchor.constraint(
                equalTo: toggle.leadingAnchor, constant: -AppSpacing.sp3
            ),
            toggle.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -padding),
            toggle.topAnchor.constraint(equalTo: contentView.topAnchor, constant: AppSpacing.sp5)
        ]
        // Top-down with an open bottom: no slack to share out.
        switchUnder = [
            contentStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -padding),
            toggle.topAnchor.constraint(equalTo: contentStack.bottomAnchor, constant: AppSpacing.sp3),
            toggle.leadingAnchor.constraint(equalTo: contentStack.leadingAnchor),
            toggle.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -AppSpacing.sp5)
        ]
        applyLayout()
    }

    /// The arrangement for the cell's content size category (#1111): today's
    /// up to `.large`; from XL (`AppTypography.stacksDenseRows`) the switch
    /// goes under the column and the flame above the title, and the title and
    /// the chain wrap — the chain only at its arrows, since each amount is
    /// joined by narrow no-break spaces. Beside the flame, «Прогрессивный»
    /// alone is wider than a 375pt card's column at 2×.
    private func applyLayout() {
        let stacked = AppTypography.stacksDenseRows(traitCollection.preferredContentSizeCategory)
        NSLayoutConstraint.deactivate(stacked ? switchBeside : switchUnder)
        NSLayoutConstraint.activate(stacked ? switchUnder : switchBeside)
        headerRow.axis = stacked ? .vertical : .horizontal
        headerRow.alignment = stacked ? .leading : .center
        titleLabel.numberOfLines = stacked ? 0 : 1
        chainLabel.numberOfLines = stacked ? 0 : 1
        chainLabel.adjustsFontSizeToFitWidth = !stacked
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onToggled = nil
    }

    // MARK: - Configure

    /// - Parameters:
    ///   - isOn: Whether progressive mode is armed.
    ///   - chain: Raw wallet-unit amounts (base, ×2, ×4, ×8).
    ///   - accessibilityChain: Spoken form of the chain («1-е: 50 ₽ → …»).
    func configure(isOn: Bool, chain: [Double], currency: Currency, accessibilityChain: String) {
        toggle.isOn = isOn
        self.chain = chain
        self.currency = currency
        self.accessibilityChain = accessibilityChain
        applyArmedAppearance(isOn)
    }

    // MARK: - Actions

    @objc private func toggled() {
        applyArmedAppearance(toggle.isOn)
        onToggled?(toggle.isOn)
    }

    /// Off keeps the card's texture (#688): the chain stays on screen, muted
    /// to neutral ink, and the flame stays pain-tinted at the app's disabled
    /// alpha instead of fading to grey. The canon only draws the armed card
    /// (`docs/design/snoozepay-2026-04-27/project/components/SPMore2.jsx:257-280`),
    /// so the off state follows the app's existing
    /// disabled row (`SoundPickerRowCell`, alpha 0.45).
    private func applyArmedAppearance(_ isOn: Bool) {
        iconView.tintColor = AppColors.pain400
        iconView.alpha = isOn ? 1 : Self.disabledFlameAlpha
        chainLabel.isHidden = false
        chainLabel.attributedText = Self.chainText(
            for: chain, currency: currency, isArmed: isOn, traits: traitCollection
        )
        // A UILabel takes no touches, so the chain is not interactive in
        // either state; VoiceOver is told the rule is off rather than reading
        // the prices as if they applied. Exactly one off signal (#1113): the
        // spoken «Выключено» prefix. The chain is static text, not a disabled
        // control, so `.notEnabled` («недоступно») would repeat the off state
        // and wrongly suggest something here could be enabled by tapping it.
        chainLabel.accessibilityLabel = isOn
            ? accessibilityChain
            : Localized.format("create_alarm.progressive.chain_off_accessibility", accessibilityChain)
        chainLabel.accessibilityTraits = .staticText
        surface.setPainTinted(isOn)
    }

    /// Same dimming as a disabled `SoundPickerRowCell` row.
    static let disabledFlameAlpha: CGFloat = 0.45

    // MARK: - Chain rendering

    /// `50 → 100 → 200 → 400 ₽` per `SPMore2.jsx`: the first two steps are
    /// warn-tinted (still affordable), the back half pain-tinted, and the
    /// final step renders bold at 16pt with the wallet currency via
    /// `MoneyFormatter` so the narrow-space rule holds.
    ///
    /// Disarmed, every step takes `fg3` — the card's own meta ink — so the
    /// shape and numbers stay but nothing reads as a live price.
    ///
    /// Both sizes grow along `.subheadline` at `traits`' content size
    /// category, so the last step keeps its lead over the others (#1111).
    private static func chainText(
        for chain: [Double], currency: Currency, isArmed: Bool, traits: UITraitCollection
    ) -> NSAttributedString {
        guard chain.count == 4 else { return NSAttributedString() }
        let stepFont = AppTypography.scaled(AppFonts.mono(.semibold, 14), as: .subheadline, compatibleWith: traits)
        let arrowAttributes: [NSAttributedString.Key: Any] = [
            .font: stepFont,
            .foregroundColor: AppColors.fg4
        ]
        let stepColors: [UIColor] = isArmed
            ? [AppColors.warn400, AppColors.warn400, AppColors.pain400]
            : [AppColors.fg3, AppColors.fg3, AppColors.fg3]

        let result = NSMutableAttributedString()
        for (index, value) in chain.prefix(3).enumerated() {
            result.append(NSAttributedString(
                string: MoneyFormatter.quotedDigits(value, currency: currency) ?? "—",
                attributes: [.font: stepFont, .foregroundColor: stepColors[index]]
            ))
            result.append(NSAttributedString(string: " → ", attributes: arrowAttributes))
        }
        result.append(MoneyFormatter.quotedAttributed(
            chain[3], currency: currency,
            digitsFont: AppTypography.scaled(AppFonts.mono(.bold, 16), as: .subheadline, compatibleWith: traits),
            color: isArmed ? AppColors.pain400 : AppColors.fg3
        ))
        return result
    }
}

// MARK: - Pain-tintable card surface

/// Card background for `ProgressiveScaleCell`. Default state mirrors the
/// generic `styleAsCardRow` recipe (`bg1` fill + brand shadow + `stroke1`
/// hairline); the armed state overlays the V2 pain gradient
/// (`135deg rgba(244,82,63,.10) → rgba(244,82,63,.02)`) and swaps the hairline
/// for the pain tint per `SPMore2.jsx`.
///
/// `internal` rather than file-private so the light-theme regression tests can
/// host it in a window — the decoration only resolves correctly inside a real
/// hierarchy (see `CreateAlarmLightThemeTests`).
final class ProgressiveCardSurface: UIView {

    /// Whether the card is currently showing its armed (pain-tinted) state.
    /// Kept so a theme flip can repaint the right hairline without the cell
    /// having to re-`configure`.
    private var isPainTinted = false

    /// The card's corner radius — deliberately LARGER than the canon's
    /// `radius={20}` (`SPScreensV2.jsx`), because on this screen 20 is not
    /// reachable.
    ///
    /// `UITableView` masks an `.insetGrouped` cell's `backgroundView` to the
    /// SECTION's own rounded rect, whose radius measured ~25pt on iOS 26.
    /// The mask is installed after our `layoutSubviews`, so a runtime dump
    /// taken there reports `mask=nil` and is misleading. What gives it away
    /// is that the rendered corner does not follow this constant at all:
    /// set to 4, the card still drew a ~25pt arc, and a green fill proved the
    /// pixels were ours.
    ///
    /// Any outline we stroke at a radius BELOW the mask's bulges past it at
    /// the corner and is clipped away — which is exactly the reported bug:
    /// a solid line along the straight edges, nothing on the arc. Measured
    /// with a 2pt probe, 12 and 20 failed identically. Above the mask's
    /// radius our own shape has less material than the mask everywhere, so
    /// nothing is clipped and fill and stroke describe one curve.
    /// `AppRadius.xl` (28) is the smallest step on the scale that clears it.
    ///
    /// `CardRowBackgroundView` has the same clipped corner and always has —
    /// invisibly, because `stroke1` is one device pixel. Here the outline is
    /// pain-tinted, so the gap reads. Raising it app-wide is #689's fork.
    private static let cardRadius = AppRadius.xl

    /// The card's outline, stroked as a path rather than set as
    /// `layer.borderWidth`.
    ///
    /// `borderWidth` is rendered by CoreAnimation as the ring between the
    /// layer's rounded rect and an inset one, and that ring is NOT of uniform
    /// width around a corner. Measured on this card with a 2pt probe: 1.3pt of
    /// stroke at each tangent, 0.2pt at 20° and 70° into the arc, and nothing
    /// at all at 45°. A stroked path has one line width everywhere, which is
    /// why `CardRowBackgroundView` already draws its outline this way.
    private let outline = CAShapeLayer()

    private let gradient: CAGradientLayer = {
        let layer = CAGradientLayer()
        layer.startPoint = CGPoint(x: 0, y: 0)
        layer.endPoint = CGPoint(x: 1, y: 1)
        layer.cornerRadius = ProgressiveCardSurface.cardRadius
        // Same curve as the surface it sits on, or the ramp's own corner
        // shows past the card's on the arc.
        layer.cornerCurve = .circular
        // `cornerRadius` alone does not clip a CAGradientLayer: the ramp is
        // the layer's CONTENT, and content is only clipped when the layer
        // masks. Without this the armed card painted a square gradient
        // under a rounded border, so each corner showed the ramp's own
        // square edge outside the stroke and read as a different colour.
        layer.masksToBounds = true
        layer.isHidden = true
        return layer
    }()

    init() {
        super.init(frame: .zero)
        // `bg1`, not the system `secondarySystemBackground`: identical
        // `#FFFFFF` in light, but the brand `#0E1320` in dark instead of the
        // system's warm `#1C1C1E`. Every sibling section on this form is
        // painted by `CardRowBackgroundView`, which moved onto `bg1` in #496 —
        // this card was the last one still reading a different dark grey.
        backgroundColor = AppColors.bg1
        layer.cornerRadius = ProgressiveCardSurface.cardRadius
        // `.circular` EXPLICITLY: iOS 26 defaults `cornerCurve` to
        // `.continuous`, and a squircle of this radius carries its corner
        // ~1.4x further from the tangent than the circular arc `outline`
        // strokes. Leaving the default would put the fill back outside the
        // stroke and reopen the gap this radius was raised to close.
        layer.cornerCurve = .circular
        // Deliberately NOT `.continuous`. `backgroundColor` is clipped to the
        // squircle a continuous curve describes, but `borderWidth` is still
        // stroked along the CIRCULAR arc of the same radius — and the two
        // diverge most at 45°. Measured on this card at a 2pt probe width:
        // 1.3pt of stroke at either tangent, 0.2pt at 20° and 70°, and NONE
        // at 45°, all of it sitting inside the fill edge (r 17.7-19.0 against
        // a fill boundary at 20). Circular corners keep fill and border on
        // one curve, which is what every other card in the app already uses.
        layer.masksToBounds = false
        layer.addSublayer(gradient)
        outline.fillColor = UIColor.clear.cgColor
        layer.addSublayer(outline)
        applyThemedDecoration()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: ProgressiveCardSurface, _) in
            view.applyThemedDecoration()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
        outline.frame = bounds
        // Inset by half the line width so the stroke lands ON the card's
        // edge instead of straddling it, and pull the radius in by the
        // same amount so the inset path stays concentric with the fill.
        let half = outline.lineWidth / 2
        outline.path = UIBezierPath(
            roundedRect: bounds.insetBy(dx: half, dy: half),
            cornerRadius: max(0, ProgressiveCardSurface.cardRadius - half)
        ).cgPath
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: ProgressiveCardSurface.cardRadius).cgPath
        // Light mode's `shadow1` is a two-stop recipe; the narrow ambient stop
        // lives on a sibling sublayer that has to track the host's bounds.
        AppShadow.installAmbientShadow1Layer(
            on: layer,
            cornerRadius: ProgressiveCardSurface.cardRadius,
            trait: traitCollection
        )
    }

    func setPainTinted(_ isOn: Bool) {
        isPainTinted = isOn
        gradient.isHidden = !isOn
        applyThemedDecoration()
    }

    /// Re-resolve everything that caches a `cgColor` or branches on theme.
    ///
    /// The hairline is no longer armed-only: on the light page a white card on
    /// `#F4F6FB` is 1.06:1 of separation, so the border is what draws the card
    /// edge — the shadow alone leaves a floating slab. Disarmed the stroke is
    /// the neutral `stroke1` every other card uses; armed it becomes the pain
    /// tint from `SPMore2.jsx`.
    private func applyThemedDecoration() {
        AppShadow.shadow1(for: traitCollection).apply(to: layer)
        AppShadow.installAmbientShadow1Layer(
            on: layer,
            cornerRadius: ProgressiveCardSurface.cardRadius,
            trait: traitCollection
        )
        gradient.colors = [
            AppColors.pain500.resolvedColor(with: traitCollection).withAlphaComponent(0.10).cgColor,
            AppColors.pain500.resolvedColor(with: traitCollection).withAlphaComponent(0.02).cgColor
        ]
        // ## The armed outline used to be 3x every other card (#675)
        //
        // `isPainTinted ? 1 : 1.0 / scale` — a hard-coded point for the armed
        // state, one device pixel for everything else. Measured on hosted
        // views at `displayScale == 3`, that made the armed card the ONLY
        // 1.0pt outline in the app: `CardRowBackgroundView`, `applyCardStyle`
        // and this card disarmed all render 0.3333, in both themes.
        //
        // So toggling this control off dropped its own outline 1.0 -> 0.333
        // while its neighbours never moved, and that step — together with the
        // gradient going and the `50 -> 100 -> 200 -> 400 РУБ` chain hiding
        // (since #688 it stays, muted) — is what was reported as the card
        // "losing its border" when switched off. The disarmed state was never the outlier; the armed
        // one was.
        //
        // Two earlier attempts got this wrong in opposite directions: PR #682
        // thickened the disarmed state, and an earlier revision of THIS branch
        // thickened everything to 1.0 app-wide, both on measurements that read
        // `AppShadow.ambientShadow1` — a fill-only `CAShapeLayer` sitting at
        // sublayer index 0, carrying `CAShapeLayer`'s default `lineWidth` of 1
        // and never stroked — instead of the outline. Select the outline by
        // `strokeColor != nil`, never by position.
        //
        // The width is therefore the same in both states now, and arming is
        // carried by ink and the gradient, exactly as `SPMore2.jsx` draws it.
        // Whether one device pixel of `stroke1` (1.183:1 on white) is a
        // visible edge at all is a real question, and an app-wide one — the
        // fork is written up on #689 and belongs to the PM.
        outline.lineWidth = hairlineWidth
        let stroke = isPainTinted
            ? AppColors.pain500.resolvedColor(with: traitCollection).withAlphaComponent(0.25)
            : AppColors.stroke1.resolvedColor(with: traitCollection)
        outline.strokeColor = stroke.cgColor
        setNeedsLayout()
    }
}
