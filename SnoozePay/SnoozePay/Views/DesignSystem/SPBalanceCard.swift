import UIKit

/// Hero balance card — `.sp-balance` in `components.css`.
///
/// Visual: 28pt vertical / 20pt horizontal padding, `bg2` fill with a soft
/// money-tinted radial highlight in the top-right corner. Caps «Баланс»
/// header sits on top of the big mono number; optional weekly delta
/// (`↑/↓ amount за неделю`) and hint line stack underneath.
///
/// The big number ideally renders with the money gradient mask (CSS uses
/// `-webkit-background-clip: text`); CoreText doesn't expose a direct
/// equivalent so we mask a `CAGradientLayer` with the rendered glyph
/// outlines on layout to get the same effect.
final class SPBalanceCard: UIView {

    // MARK: - Subviews

    private let capsLabel = UILabel()
    private let valueLabel = SPGradientTextLabel(
        colors: SPSupport.moneyGradientColors,
        locations: SPSupport.moneyGradientLocations,
        startPoint: SPSupport.gradientStart,
        endPoint: SPSupport.gradientEnd
    )
    private let deltaLabel = UILabel()
    private let hintLabel = UILabel()
    private let radialOverlay = RadialOverlayView()

    // MARK: - State

    private(set) var balance: Decimal
    private(set) var delta: Decimal?
    private(set) var hint: String?

    // MARK: - Init

    /// - Parameters:
    ///   - balance: Current balance — formatted as integer roubles
    ///     ("12 345 ₽") via `Decimal.formattedRubles()` below.
    ///   - delta: Optional weekly net change. Positive values render with
    ///     the up arrow + money tint; negative with the down arrow + pain
    ///     tint. `nil` hides the row.
    ///   - hint: Optional secondary line (`meta` 13pt). Used for context
    ///     such as «обновлено 2 ч назад» or «ближайшее списание завтра».
    init(balance: Decimal, delta: Decimal? = nil, hint: String? = nil) {
        self.balance = balance
        self.delta = delta
        self.hint = hint
        super.init(frame: .zero)
        configure()
        update(balance: balance, delta: delta, hint: hint)
        // iOS 17 deprecated `traitCollectionDidChange(_:)` — register a
        // closure-based observer when available; the legacy override below
        // remains as a fallback for older runtimes.
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: SPBalanceCard, _) in
                view.refreshDynamicColors()
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = AppRadius.xl
        radialOverlay.layer.cornerRadius = AppRadius.xl
        radialOverlay.frame = bounds
        // The card no longer clips itself (see `configure`), so the shadow has
        // to be rasterised against the rounded path here, and the light-mode
        // ambient stop kept in sync with the bounds.
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: AppRadius.xl).cgPath
        AppShadow.installAmbientShadow1Layer(
            on: layer,
            cornerRadius: AppRadius.xl,
            trait: traitCollection
        )
    }

    @available(iOS, deprecated: 17.0, message: "Replaced by registerForTraitChanges; kept for iOS 15/16.")
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        // iOS 17+ runtimes are notified via the registered trait observer
        // (see init); skip here to avoid double-refreshing the overlay.
        if #available(iOS 17.0, *) { return }
        refreshDynamicColors()
    }

    private func refreshDynamicColors() {
        radialOverlay.setNeedsDisplay()
        // `CAGradientLayer.colors` and every `cgColor` on a `CALayer` are
        // snapshots — they do not follow a theme flip on their own.
        valueLabel.setGradientColors(valueColors(for: traitCollection))
        applyCardChrome()
    }

    /// Card surface chrome: `shadow-1` in both themes, plus a hairline border
    /// in light only.
    ///
    /// The light page is `bg0` `#F4F6FB` and this card is `bg2` `#ECEEF6` —
    /// **1.07:1** of separation. A shadow alone cannot carry that edge, which
    /// is why light also gets `stroke1`. Dark keeps the borderless card
    /// (`bg2` on `bg0` is a visible step there) — the same deviation
    /// `AlarmCell` documents.
    private func applyCardChrome() {
        let trait = traitCollection
        AppShadow.shadow1(for: trait).apply(to: layer)
        AppShadow.installAmbientShadow1Layer(
            on: layer,
            cornerRadius: AppRadius.xl,
            trait: trait
        )
        if trait.userInterfaceStyle == .dark {
            layer.borderWidth = 0
        } else {
            let scale = trait.displayScale > 0 ? trait.displayScale : 1
            layer.borderWidth = 1.0 / scale
            layer.borderColor = AppColors.stroke1.resolvedColor(with: trait).cgColor
        }
    }

    // MARK: - Zero-balance tone

    /// Whether the card is showing an empty wallet. Green is this app's "you
    /// have money, it works" signal, so a zero painted with the money ramp
    /// said things were fine at the moment snoozing stopped working — while
    /// the alarms list called the same zero a blocking state in red (#634).
    var isZeroBalance: Bool { balance <= 0 }

    /// Stops for the hero number. At zero this is a DEGENERATE gradient (three
    /// identical stops), so the glyphs paint flat without tearing down the mask
    /// the label is built around and the theme flip keeps working through the
    /// same `setGradientColors` path.
    ///
    /// The ink is `fgOnPainWash` — the token the alarms-list pill already uses
    /// for its zero, so both screens now name the state the same way. The pain
    /// RAMP would not do: it opens on `pain300`, 2.77:1 on this near-white
    /// card, under the 3:1 large-text floor even at 56pt.
    static func valueColors(isZero: Bool, trait: UITraitCollection) -> [CGColor] {
        guard isZero else { return SPSupport.moneyGradientColors(for: trait) }
        let ink = AppColors.fgOnPainWash.resolvedColor(with: trait).cgColor
        return Array(repeating: ink, count: SPSupport.moneyGradientLocations.count)
    }

    private func valueColors(for trait: UITraitCollection) -> [CGColor] {
        Self.valueColors(isZero: isZeroBalance, trait: trait)
    }

    // MARK: - Public API

    /// Update card data in-place. Cheaper than rebuilding the view when the
    /// balance updates — the same labels are reused so the gradient mask
    /// re-rasterises only when the layout cycle invalidates.
    func update(balance: Decimal, delta: Decimal? = nil, hint: String? = nil) {
        self.balance = balance
        self.delta = delta
        self.hint = hint
        // fmtRub rule: mono digits, proportional ~4pt gap before ₽ — the
        // attributed variant re-fonts the separator so it escapes the mono
        // advance grid (a plain string would render a full-cell space).
        valueLabel.attributedText = MoneyFormatter.attributed(
            balance,
            digitsFont: AppTypography.moneyXl
        )
        // Crossing zero changes the tone, not just the digits — the ink and
        // the corner highlight have to follow the new value.
        valueLabel.setGradientColors(valueColors(for: traitCollection))
        radialOverlay.isZeroBalance = isZeroBalance
        if let delta = delta {
            deltaLabel.isHidden = false
            deltaLabel.attributedText = renderDelta(delta)
        } else {
            deltaLabel.isHidden = true
        }
        if let hint = hint {
            hintLabel.text = hint
            hintLabel.isHidden = false
        } else {
            hintLabel.isHidden = true
        }
        setNeedsLayout()
    }

    // MARK: - Configuration

    private func configure() {
        backgroundColor = AppColors.bg2
        layer.cornerRadius = AppRadius.xl
        // The card must NOT clip itself — a `masksToBounds` host cannot render
        // a drop shadow, and light mode needs one. The corner clipping the
        // radial highlight relied on moves onto the overlay itself.
        layer.masksToBounds = false
        applyCardChrome()

        radialOverlay.translatesAutoresizingMaskIntoConstraints = false
        radialOverlay.layer.masksToBounds = true
        addSubview(radialOverlay)

        capsLabel.translatesAutoresizingMaskIntoConstraints = false
        capsLabel.attributedText = NSAttributedString(
            string: Localized.text("common.caps.balance"),
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: AppColors.fg3
            ]
        )

        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        // Hero balance uses `moneyXl` (56pt mono bold) per `tokens.css` L168
        // — `--sp-t-money-xl: 700 56px/60px var(--sp-font-mono)`. The bigger
        // glyphs can overflow on narrow devices for large balances
        // ("1 234 567 ₽"), so we let UIKit shrink to 75% before clipping.
        valueLabel.font = AppTypography.moneyXl
        // The gradient label keeps this fallback until its own layout pass has
        // resolved the glyph bounds, then replaces it with a masked layer.
        valueLabel.textColor = AppColors.fg1
        // The ramp is KEPT in light — measured on the light `bg2` card it runs
        // 4.55 → 6.04 → 10.61:1 (money400 → money500 → money700), so every
        // stop clears normal-text AA, let alone the 56pt large-text bar. What
        // it needed was trait resolution: the stops baked at `init` are plain
        // `CGColor`s and would otherwise keep the dark mint ramp on a white
        // card.
        valueLabel.setGradientColors(valueColors(for: traitCollection))
        valueLabel.adjustsFontForContentSizeCategory = false
        valueLabel.numberOfLines = 1
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.75

        deltaLabel.translatesAutoresizingMaskIntoConstraints = false
        deltaLabel.font = AppTypography.moneySm

        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.font = AppTypography.meta
        hintLabel.textColor = AppColors.fg3

        let stack = UIStackView(arrangedSubviews: [
            capsLabel, valueLabel, deltaLabel, hintLabel
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = AppSpacing.sp1
        stack.setCustomSpacing(AppSpacing.sp2, after: capsLabel)
        stack.setCustomSpacing(Self.deltaToHintGap, after: deltaLabel)
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: Self.verticalPadding),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.verticalPadding),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: AppSpacing.sp5),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -AppSpacing.sp5)
        ])

    }

    // MARK: - Metrics

    /// `.sp-balance` vertical padding — 28px, which is off the 4px t-shirt
    /// scale, so it is composed from grid steps rather than typed as a literal
    /// (horizontal padding is `sp5` = 20px, design v3 tightened 24 → 20).
    private static let verticalPadding = AppSpacing.sp6 + AppSpacing.sp1

    /// Gap between the weekly-delta row and the hint line — 14px in
    /// `components.css`, likewise between two grid steps.
    private static let deltaToHintGap = AppSpacing.sp3 + AppSpacing.sp1 / 2

    // MARK: - Auto-shrink mask alignment

    /// Compute the scale factor `adjustsFontSizeToFitWidth` would apply to fit
    /// `attributed` (rendered at its baked-in fonts) into `availableWidth`.
    ///
    /// Mirrors UIKit's single-line shrink heuristic: if the natural text width
    /// already fits, returns `1`; otherwise returns `availableWidth / naturalWidth`
    /// clamped to `minimumScaleFactor` (UIKit never shrinks below the floor,
    /// it clips instead — so the mask must match that clamped size, not the
    /// raw ratio). A pure function so the geometry is unit-testable without a
    /// live label / layout pass.
    static func effectiveFontScale(
        for attributed: NSAttributedString,
        fitting availableWidth: CGFloat,
        minimumScaleFactor: CGFloat
    ) -> CGFloat {
        guard availableWidth > 0, attributed.length > 0 else { return 1 }
        let naturalWidth = attributed.size().width
        guard naturalWidth > availableWidth else { return 1 }
        let ratio = availableWidth / naturalWidth
        let floor = minimumScaleFactor > 0 ? minimumScaleFactor : ratio
        return max(ratio, floor)
    }

    /// Re-font every run of `attributed` in place at `scale × pointSize`,
    /// preserving each run's traits / weight (digits stay mono, the separator
    /// stays proportional). Used to align the gradient mask with the shrunk
    /// on-screen glyphs.
    static func scaleFonts(in attributed: NSMutableAttributedString, by scale: CGFloat) {
        guard scale > 0, scale != 1 else { return }
        let full = NSRange(location: 0, length: attributed.length)
        attributed.enumerateAttribute(.font, in: full, options: []) { value, range, _ in
            guard let font = value as? UIFont else { return }
            attributed.addAttribute(
                .font,
                value: font.withSize(font.pointSize * scale),
                range: range
            )
        }
    }

    private func renderDelta(_ delta: Decimal) -> NSAttributedString {
        let arrow = delta < 0 ? "↓" : "↑"
        let abs = NSDecimalNumber(decimal: delta < 0 ? -delta : delta).decimalValue
        let str = Localized.format("wallet.balance.delta_week", arrow, abs.formattedRubles())
        let color = delta < 0 ? AppColors.pain400 : AppColors.money400
        return NSAttributedString(
            string: str,
            attributes: [
                .font: AppTypography.moneySm,
                .foregroundColor: color
            ]
        )
    }
}

// MARK: - Radial overlay

/// Internal helper view that paints the brand radial highlight behind the
/// balance card. CSS uses `radial-gradient(80% 60% at 100% 0%, rgba(46,219,159,.18))`
/// — CoreGraphics doesn't have a one-liner so we draw it in `draw(_:)`.
private final class RadialOverlayView: UIView {

    /// Swaps the corner highlight from money to pain while the wallet is
    /// empty. Without this the zero number would sit in pain ink on a green
    /// glow — the card would still be telling both stories at once (#634).
    var isZeroBalance = false {
        didSet {
            guard isZeroBalance != oldValue else { return }
            setNeedsDisplay()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        // Resolve against this view's own traits rather than letting `.cgColor`
        // snapshot `UITraitCollection.current`: the highlight has to be the
        // dark-theme mint on `bg2` and the light-theme deep green on the
        // near-white card (pain's equivalents while the wallet is empty), and
        // `draw(_:)` is not a safe place to assume which trait collection is
        // current.
        let tint = (isZeroBalance ? AppColors.pain400 : AppColors.money400)
            .resolvedColor(with: traitCollection)
            .withAlphaComponent(0.18)
        let colors = [tint.cgColor, UIColor.clear.cgColor]
        guard let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: colors as CFArray,
            locations: [0.0, 1.0]
        ) else { return }
        // 80% wide × 60% tall radial centred at top-right corner.
        let centerPoint = CGPoint(x: rect.maxX, y: rect.minY)
        let radius = max(rect.width, rect.height) * 0.6
        context.drawRadialGradient(
            gradient,
            startCenter: centerPoint,
            startRadius: 0,
            endCenter: centerPoint,
            endRadius: radius,
            options: []
        )
    }
}

// MARK: - Decimal formatting

extension Decimal {
    /// Format as integer roubles using the locale-aware `ru-RU` thousands
    /// separator and a trailing `₽` glyph, e.g. `1 234 ₽`. Truncates the
    /// fractional component — the design system never shows kopecks on the
    /// balance card.
    /// Delegates to `MoneyFormatter` — the single fmtRub implementation —
    /// so every legacy `formattedRubles()` call site picks up the design-v3
    /// narrow space before `₽` without churning each caller.
    func formattedRubles() -> String {
        MoneyFormatter.string(self)
    }
}
