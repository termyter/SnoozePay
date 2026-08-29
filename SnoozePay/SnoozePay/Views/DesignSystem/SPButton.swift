import UIKit

/// Branded button primitive matching the `.sp-btn` recipe in
/// `docs/design/snoozepay-2026-04-27/project/components/components.css`.
///
/// Three axes:
/// - `Variant`: visual chrome (gradient fills for money/pain/warn,
///   stroked-transparent for ghost, faint overlay for quiet).
/// - `Size`: 56pt / 48pt / 36pt heights with matching typography ramps.
/// - Optional `icon` (left) and `suffix` (right, mono-font) decorations.
///
/// All gradient variants install a `CAGradientLayer` at the bottom of the
/// view's layer tree and refresh it on layout / trait changes — `tintColor`
/// alone can't reproduce the 3-stop diagonal sweep the design calls for.
final class SPButton: UIControl {

    // MARK: - Variants

    enum Variant {
        case money   // Primary CTA — money gradient + fgOnMoney text.
        case pain    // Stop / delete / progressive snooze — pain gradient.
        case warn    // Default snooze — warn gradient.
        case ghost   // Transparent fill, stroke2 border.
        case quiet   // No chrome, faint overlay fill.
    }

    // Short cases mirror the JSX spec (`size="lg"`/`"md"`/`"sm"`) and the
    // `--sp-btn--{lg,md,sm}` CSS modifiers — keeping the names here makes
    // grep across CSS / JSX / Swift trivial.
    // swiftlint:disable identifier_name
    enum Size {
        case lg   // 56pt — primary CTA
        case md   // 48pt — secondary actions
        case sm   // 36pt — chips / inline buttons
        // swiftlint:enable identifier_name

        var height: CGFloat {
            switch self {
            case .lg: return 56
            case .md: return 48
            case .sm: return 36
            }
        }

        var horizontalPadding: CGFloat {
            // Design v3 tightened `.sp-btn` paddings: 0 24px → 0 20px,
            // sm 0 14px → 0 12px (`components.css`).
            switch self {
            case .lg, .md: return AppSpacing.sp5   // 20pt
            case .sm:      return AppSpacing.sp3   // 12pt
            }
        }

        var labelFont: UIFont {
            switch self {
            case .lg: return AppFonts.sans(.bold, 17)
            case .md: return AppTypography.button
            case .sm: return AppTypography.buttonSm
            }
        }

        var cornerRadius: CGFloat {
            // `.sp-btn--lg` overrides the base `--sp-r-md` with `--sp-r-lg`
            // (20pt); `--md` inherits the 16pt base; `--sm` drops to `--sp-r-sm`
            // (12pt). Matches `components.css:18-20`.
            switch self {
            case .lg: return AppRadius.lg          // 20pt — matches sp-r-lg
            case .md: return AppRadius.md          // 16pt — matches sp-r-md
            case .sm: return AppRadius.sm          // 12pt — matches sp-r-sm
            }
        }

        var iconSize: CGFloat {
            switch self {
            case .lg: return 20
            case .md: return 18
            case .sm: return 16
            }
        }
    }

    // MARK: - Configuration

    let variant: Variant
    let size: Size

    // MARK: - State

    /// Override `isEnabled` to refresh visual state — UIControl's default
    /// implementation only flips a property, not the rendered appearance.
    override var isEnabled: Bool {
        didSet { refreshDisabledAppearance() }
    }

    override var isHighlighted: Bool {
        didSet { SPSupport.animatePress(self, pressed: isHighlighted) }
    }

    /// `false` by default — caller sizes the button explicitly. When `true`
    /// the button stretches to match its superview width via the trailing
    /// constraint installed by the parent.
    var isFullWidth: Bool = false {
        didSet {
            updateSuffixSpacer()
            invalidateIntrinsicContentSize()
        }
    }

    /// Optional heavier stroke for `.ghost` buttons that need to read as a
    /// stronger affordance than the default hairline (e.g. the firing
    /// «Я встал — выключить» CTA — 1.5pt white .22 per `SPThemedFiring.jsx:
    /// 188-203`). Nil keeps the default `1/scale` stroke2 hairline. Applied in
    /// `applyVariant`, so it survives trait-change re-tints.
    var ghostBorderOverride: (width: CGFloat, color: UIColor)? {
        didSet { if variant == .ghost { applyVariant() } }
    }

    // MARK: - Subviews

    private let stack = UIStackView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let suffixLabel = UILabel()
    /// Flexible gap that pushes the suffix to the trailing edge — mirrors the
    /// CSS `.sp-btn__suffix { margin-left: auto }`. Only inflated (and only
    /// hugs at a low priority) when the button is full-width *and* carries a
    /// suffix; otherwise it collapses so a hugging button stays centred.
    private let suffixSpacer = UIView()
    private var gradientLayer: CAGradientLayer?
    /// Edge pins toggled on for full-width + suffix layouts (see
    /// `updateSuffixSpacer`).
    private var stackLeadingPin: NSLayoutConstraint?
    private var stackTrailingPin: NSLayoutConstraint?

    // MARK: - Init

    /// - Parameters:
    ///   - title: Button label.
    ///   - variant: Visual chrome.
    ///   - size: Vertical scale. Defaults to `.lg`.
    ///   - icon: Optional leading image (rendered as template, tinted to
    ///     match the label colour).
    ///   - suffix: Optional trailing mono-font string (used for amounts,
    ///     e.g. "−50 ₽" suffixes on quick-pay buttons).
    ///   - fullWidth: When `true`, intrinsic width returns `noIntrinsicMetric`
    ///     so the caller can pin the button to its superview's width.
    init(
        title: String,
        variant: Variant = .money,
        size: Size = .lg,
        icon: UIImage? = nil,
        suffix: String? = nil,
        fullWidth: Bool = false
    ) {
        self.variant = variant
        self.size = size
        self.isFullWidth = fullWidth
        super.init(frame: .zero)
        configureLayout()
        titleLabel.text = title
        if let icon = icon {
            iconView.image = icon.withRenderingMode(.alwaysTemplate)
            iconView.isHidden = false
        } else {
            iconView.isHidden = true
        }
        if let suffix = suffix {
            suffixLabel.text = suffix
            suffixLabel.isHidden = false
        } else {
            suffixLabel.isHidden = true
        }
        updateSuffixSpacer()
        applyVariant()
        refreshDisabledAppearance()
        // Expose the button as a SINGLE accessibility element rather than
        // leaking its internal title/suffix UILabels as separate staticTexts.
        // VoiceOver then reads one "button" with the combined label, and UI
        // tests can target it via `accessibilityIdentifier`. The combined
        // label joins the title with the optional mono suffix (e.g. amount).
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = [title, suffix].compactMap { $0 }.joined(separator: ", ")
        // iOS 17 deprecated `traitCollectionDidChange(_:)` — register a
        // closure-based observer when available; the legacy override below
        // remains as a fallback for older runtimes.
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: SPButton, _) in
                view.applyVariant()
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout

    override var intrinsicContentSize: CGSize {
        // Honour `isFullWidth` by returning .noIntrinsicMetric for the width
        // axis — caller pins to superview / stack so the button stretches.
        let height = size.height
        if isFullWidth {
            return CGSize(width: UIView.noIntrinsicMetric, height: height)
        }
        let stackSize = stack.systemLayoutSizeFitting(
            UIView.layoutFittingCompressedSize
        )
        return CGSize(
            width: stackSize.width + size.horizontalPadding * 2,
            height: height
        )
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer?.frame = bounds
        // Inset the shadow path by 6pt to reproduce the CSS `-6` spread on the
        // brand-coloured shadows (`--sp-shadow-{money,pain,warn}`), so the glow
        // sits tucked under the button rather than haloing past its edges.
        let spreadInset: CGFloat = layer.shadowOpacity > 0 && layer.borderWidth == 0 ? 6 : 0
        layer.shadowPath = UIBezierPath(
            roundedRect: bounds.insetBy(dx: spreadInset, dy: spreadInset),
            cornerRadius: max(size.cornerRadius - spreadInset, 0)
        ).cgPath
    }

    @available(iOS, deprecated: 17.0, message: "Replaced by registerForTraitChanges; kept for iOS 15/16.")
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        // iOS 17+ runtimes get the same callback through the registered
        // trait observer (see init); skip here so we don't refresh twice.
        if #available(iOS 17.0, *) { return }
        applyVariant()
    }

    // MARK: - Configuration internals

    private func configureLayout() {
        layer.cornerRadius = size.cornerRadius
        layer.masksToBounds = false

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.setContentHuggingPriority(.required, for: .horizontal)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = size.labelFont
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontForContentSizeCategory = false

        suffixLabel.translatesAutoresizingMaskIntoConstraints = false
        // Mono font for trailing amount suffixes — matches CSS recipe
        // `font-family: var(--sp-font-mono)`. The design dropped the legacy
        // `opacity: .85` dim, so the suffix now reads at full foreground
        // weight (`components.css:22`).
        suffixLabel.font = size == .sm ? AppTypography.moneySm : AppTypography.moneyMd
        suffixLabel.textAlignment = .right
        suffixLabel.setContentHuggingPriority(.required, for: .horizontal)

        suffixSpacer.translatesAutoresizingMaskIntoConstraints = false
        // Hugs weakly so it only stretches when the stack has slack (full-width
        // buttons); a hugging button keeps it collapsed and stays centred.
        suffixSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        suffixSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = AppSpacing.sp2     // 8pt — matches `gap: 8px`
        stack.alignment = .center
        stack.isUserInteractionEnabled = false
        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(suffixSpacer)
        stack.addArrangedSubview(suffixLabel)
        addSubview(stack)

        // Centre the content for hugging buttons; lower the priority so the
        // full-width edge constraints can override it when the suffix needs to
        // be pinned to the trailing edge.
        let centerX = stack.centerXAnchor.constraint(equalTo: centerXAnchor)
        centerX.priority = .defaultHigh
        // Pin the stack to both edges — toggled on only for full-width buttons
        // carrying a suffix so the flexible spacer can stretch and shove the
        // suffix to the trailing edge (`margin-left: auto`).
        stackLeadingPin = stack.leadingAnchor.constraint(
            equalTo: leadingAnchor, constant: size.horizontalPadding
        )
        stackTrailingPin = stack.trailingAnchor.constraint(
            equalTo: trailingAnchor, constant: -size.horizontalPadding
        )

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: size.height),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(
                greaterThanOrEqualTo: leadingAnchor,
                constant: size.horizontalPadding
            ),
            stack.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor,
                constant: -size.horizontalPadding
            ),
            centerX,
            iconView.widthAnchor.constraint(equalToConstant: size.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: size.iconSize)
        ])
    }

    /// Stretch the stack edge-to-edge (and let the flexible spacer expand) only
    /// when the button is full-width *and* carries a suffix; otherwise collapse
    /// the spacer so a hugging / suffix-less button stays centred.
    private func updateSuffixSpacer() {
        let active = isFullWidth && !suffixLabel.isHidden
        suffixSpacer.isHidden = !active
        stackLeadingPin?.isActive = active
        stackTrailingPin?.isActive = active
    }

    private func applyVariant() {
        gradientLayer?.removeFromSuperlayer()
        gradientLayer = nil
        layer.borderWidth = 0
        layer.shadowOpacity = 0

        switch variant {
        // The trait-explicit `SPSupport` overloads, not the plain computed
        // properties: those snapshot `UITraitCollection.current`, which inside
        // a view method is not necessarily this button's trait collection.
        // `applyVariant()` re-installs the layer on every flip, so the stops
        // themselves are never stale — only mis-resolved without this.
        case .money:
            installGradient(
                colors: SPSupport.moneyGradientColors(for: traitCollection),
                locations: SPSupport.moneyGradientLocations
            )
            applyColoredShadow(color: AppColors.money500)
            setForeground(AppColors.fgOnMoney)
        case .pain:
            installGradient(
                colors: SPSupport.painGradientColors(for: traitCollection),
                locations: SPSupport.painGradientLocations
            )
            applyColoredShadow(color: AppColors.pain500, painLike: true)
            setForeground(AppColors.fgOnPain)
        case .warn:
            installGradient(
                colors: SPSupport.warnGradientColors(for: traitCollection),
                locations: SPSupport.warnGradientLocations
            )
            applyColoredShadow(color: AppColors.warnFill500)
            setForeground(AppColors.fgOnWarn)
        case .ghost:
            backgroundColor = .clear
            if let override = ghostBorderOverride {
                layer.borderWidth = override.width
                layer.borderColor = override.color.resolvedColor(with: traitCollection).cgColor
            } else {
                // `.sp-btn--ghost { border: 1px solid var(--sp-stroke-2) }` —
                // a flat 1pt, not a sub-pixel hairline, so the affordance reads
                // clearly across scales (`components.css:47`).
                layer.borderWidth = 1.0
                layer.borderColor = AppColors.stroke2.resolvedColor(with: traitCollection).cgColor
            }
            setForeground(AppColors.fg1)
        case .quiet:
            backgroundColor = AppColors.whiteOverlay06
            setForeground(AppColors.fg1)
        }
        // Refresh the brand-shadow path (and gradient frame) for the new chrome —
        // a trait change re-tints here but doesn't guarantee a layout pass.
        setNeedsLayout()
    }

    private func installGradient(colors: [CGColor], locations: [NSNumber]) {
        let gradient = CAGradientLayer()
        gradient.colors = colors
        gradient.locations = locations
        gradient.startPoint = SPSupport.gradientStart
        gradient.endPoint = SPSupport.gradientEnd
        gradient.cornerRadius = size.cornerRadius
        // Size the layer to the current bounds up front. `applyVariant()` runs
        // on trait changes when the button is already laid out, and re-inserting
        // a sublayer doesn't itself trigger `layoutSubviews` — without this the
        // fresh gradient would sit at `.zero` frame (invisible), leaving only the
        // dark on-money text so the CTA reads as disabled (#320). `layoutSubviews`
        // keeps it in sync afterwards and corrects the cold-start case where
        // `bounds` is still zero at first install.
        gradient.frame = bounds
        layer.insertSublayer(gradient, at: 0)
        gradientLayer = gradient
        backgroundColor = .clear
    }

    private func applyColoredShadow(color: UIColor, painLike: Bool = false) {
        // `--sp-shadow-{money,warn}: 0 8px 22px -6px rgba(...,.40)`,
        // `--sp-shadow-pain: ... .45`. CSS blur 22 ≈ CALayer shadowRadius 11
        // (CALayer radius is roughly half the CSS blur). The −6 spread is
        // reproduced by insetting the shadowPath in `layoutSubviews`.
        layer.shadowColor = color.resolvedColor(with: traitCollection).cgColor
        let base: Float = painLike ? 0.45 : 0.40
        layer.shadowOpacity = traitCollection.userInterfaceStyle == .light ? base - 0.10 : base
        layer.shadowOffset = CGSize(width: 0, height: 8)
        layer.shadowRadius = 11
    }

    private func setForeground(_ color: UIColor) {
        titleLabel.textColor = color
        suffixLabel.textColor = color
        iconView.tintColor = color
    }

    private func refreshDisabledAppearance() {
        // CSS recipe `is-disabled { opacity: .35; box-shadow: none;
        // filter: grayscale(.5); }` — we drop the shadow + alpha; the
        // grayscale hint is too expensive on a CALayer for the tiny visual
        // win, so we instead darken via reduced alpha which reads similarly.
        alpha = isEnabled ? 1.0 : 0.35
        if !isEnabled {
            layer.shadowOpacity = 0
        } else {
            applyVariant()
        }
    }
}
