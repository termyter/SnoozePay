import UIKit

/// Standalone card surface for the SnoozePay design system.
///
/// Replaces `CardView` long-term. The legacy `applyCardStyle()` extension on
/// `UIView` and the standalone `CardView` class continue to work as thin
/// wrappers around the same recipe so the 30+ existing call sites (Settings,
/// Statistics, CreateAlarm, TopUp, ...) keep compiling. New screens reach for
/// `SPCard(tone:)` directly.
///
/// Tones map onto the `.sp-card--*` modifiers in
/// `docs/design/snoozepay-2026-04-27/project/components/components.css`.
final class SPCard: UIView {

    // MARK: - Tone

    /// Visual style of the card.
    /// - `.surface`: default — `bg1` fill, hairline stroke, soft shadow. In
    ///   light mode the stroke + shadow are required for visibility per
    ///   `feedback_design_system_consistency.md`.
    /// - `.raised`: stronger surface (`bg2`) for sheets / hero panels.
    /// - `.outline`: transparent fill, 1px `stroke2` border, no shadow.
    /// - `.money` / `.pain` / `.warn`: brand-gradient fills with matching
    ///   coloured shadow recipes.
    enum Tone {
        case surface
        case raised
        case outline
        case money
        case pain
        case warn
    }

    // MARK: - Configuration

    let tone: Tone
    let cardCornerRadius: CGFloat
    /// Inset applied uniformly on all four sides via `layoutMargins`. Subviews
    /// constrained to `layoutMarginsGuide` automatically pick up the padding.
    let cardPadding: CGFloat

    // MARK: - Internal layers

    /// Optional gradient layer for `.money`/`.pain`/`.warn` tones — added as a
    /// sublayer at zero index so subviews stack above it. Nil for non-gradient
    /// tones to keep the layer tree shallow.
    private var gradientLayer: CAGradientLayer?

    // MARK: - Init

    /// - Parameters:
    ///   - tone: Visual style. Defaults to `.surface`.
    ///   - padding: Uniform inset for `layoutMarginsGuide`. Defaults to 20pt
    ///     (matching the JSX spec `padding = 20`).
    ///   - cornerRadius: Corner radius. Defaults to `AppRadius.lg` (20pt) —
    ///     larger than the legacy 12pt `AppRadius.sm` so SPCards read as a
    ///     visibly different primitive from `applyCardStyle()` cards.
    init(
        tone: Tone = .surface,
        padding: CGFloat = AppSpacing.sp5,
        cornerRadius: CGFloat = AppRadius.lg
    ) {
        self.tone = tone
        self.cardPadding = padding
        self.cardCornerRadius = cornerRadius
        super.init(frame: .zero)
        configure()
        registerTraitObserver()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer?.frame = bounds
        // Pre-rasterise the shadow so the card doesn't pay the per-pixel
        // offscreen pass during scrolling.
        if needsShadow {
            layer.shadowPath = UIBezierPath(
                roundedRect: bounds,
                cornerRadius: cardCornerRadius
            ).cgPath
        }
        // Surface tone uses the two-stop `shadow1` recipe in light mode; the
        // narrow ambient stop lives on a sibling sublayer that needs its
        // frame + path resized whenever the host's bounds change.
        if tone == .surface {
            AppShadow.installAmbientShadow1Layer(
                on: layer,
                cornerRadius: cardCornerRadius,
                trait: traitCollection
            )
        }
    }

    /// iOS 17 deprecated `traitCollectionDidChange(_:)` in favour of the
    /// closure-based `registerForTraitChanges(_:handler:)` API. Register
    /// the handler when available; on iOS 15/16 fall back to the legacy
    /// override so light/dark switches still re-resolve dynamic colours.
    /// CALayer's `cgColor` properties don't auto-resolve dynamic UIColors,
    /// so the refresh installs the recipe again on every theme flip.
    private func registerTraitObserver() {
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: SPCard, _) in
                view.refreshDynamicColors()
            }
        }
    }

    @available(iOS, deprecated: 17.0, message: "Replaced by registerForTraitChanges; kept for iOS 15/16.")
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if #available(iOS 17.0, *) { return }
        refreshDynamicColors()
    }

    // MARK: - Configuration internals

    private var needsShadow: Bool {
        switch tone {
        case .surface, .raised, .money, .pain, .warn: return true
        case .outline: return false
        }
    }

    private func configure() {
        layer.cornerRadius = cardCornerRadius
        layer.masksToBounds = false
        layoutMargins = UIEdgeInsets(
            top: cardPadding, left: cardPadding,
            bottom: cardPadding, right: cardPadding
        )
        applyTone()
    }

    private func applyTone() {
        // Reset every property each call so re-applying after a token swap
        // can't leave stale state behind.
        gradientLayer?.removeFromSuperlayer()
        gradientLayer = nil
        layer.borderWidth = 0
        layer.shadowOpacity = 0

        switch tone {
        case .surface:
            backgroundColor = AppColors.bg1
            // `.sp-card { box-shadow: var(--sp-shadow-1) }` with no border in
            // the canon. Dark mode keeps the stroke off (the shadow + bg1/bg0
            // contrast carry the edge); light mode adds a hairline per
            // `feedback_design_system_consistency.md` where the near-white
            // surfaces would otherwise merge into the page.
            applyHairlineStrokeIfLight()
            applyShadow1()
        case .raised:
            backgroundColor = AppColors.bg2
            // `.sp-card--raised` only swaps the fill to bg2 — it inherits the
            // base `.sp-card` `--sp-shadow-1`, not the heavier shadow-2 (which
            // the canon reserves for sheets/overlays). Light mode keeps the
            // hairline so bg2 (#ECEEF6) doesn't merge into bg0 (#F4F6FB).
            applyRaisedHairlineIfLight()
            applyShadow1()
        case .outline:
            backgroundColor = .clear
            applyOutlineStroke()
        case .money:
            backgroundColor = .clear
            installGradient(
                colors: SPSupport.moneyGradientColors,
                locations: SPSupport.moneyGradientLocations
            )
            applyColoredShadow(.money)
        case .pain:
            backgroundColor = .clear
            installGradient(
                colors: SPSupport.painGradientColors,
                locations: SPSupport.painGradientLocations
            )
            applyColoredShadow(.pain)
        case .warn:
            backgroundColor = .clear
            installGradient(
                colors: SPSupport.warnGradientColors,
                locations: SPSupport.warnGradientLocations
            )
            applyColoredShadow(.warn)
        }
    }

    private func applyHairlineStrokeIfLight() {
        guard traitCollection.userInterfaceStyle != .dark else {
            layer.borderWidth = 0
            return
        }
        let scale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 1
        layer.borderWidth = 1.0 / scale
        layer.borderColor = AppColors.stroke1.resolvedColor(with: traitCollection).cgColor
    }

    private func applyOutlineStroke() {
        let scale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 1
        layer.borderWidth = 1.0 / scale
        layer.borderColor = AppColors.stroke2.resolvedColor(with: traitCollection).cgColor
    }

    private func applyShadow1() {
        // Wider/key stop on the host layer; the narrow ambient stop is
        // installed as a sibling sublayer in `layoutSubviews` (ambient layer
        // also needs its frame to track host bounds, so layout is the
        // canonical owner). `installAmbientShadow1Layer` is also called here
        // so a theme flip immediately removes/re-adds the ambient sublayer
        // without waiting for the next layout pass.
        AppShadow.shadow1(for: traitCollection).apply(to: layer)
        AppShadow.installAmbientShadow1Layer(
            on: layer,
            cornerRadius: cardCornerRadius,
            trait: traitCollection
        )
    }

    private func applyRaisedHairlineIfLight() {
        guard traitCollection.userInterfaceStyle != .dark else {
            layer.borderWidth = 0
            return
        }
        let scale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 1
        layer.borderWidth = 1.0 / scale
        layer.borderColor = AppColors.stroke1.resolvedColor(with: traitCollection).cgColor
    }

    private func applyColoredShadow(_ kind: ColoredShadow) {
        // `--sp-shadow-{money,pain,warn}: 0 8px 22px -6px rgba(...,.40)`. The
        // CSS uses a negative spread we can't replicate on CALayer, so fold
        // it into a slightly tighter offset + radius pair that still reads
        // as "this card glows brand-coloured".
        let color: UIColor
        switch kind {
        case .money: color = AppColors.money500
        case .pain:  color = AppColors.pain500
        case .warn:  color = AppColors.warn500
        }
        layer.shadowColor = color.cgColor
        layer.shadowOpacity = traitCollection.userInterfaceStyle == .light ? 0.30 : 0.40
        layer.shadowOffset = CGSize(width: 0, height: 8)
        layer.shadowRadius = 16
    }

    private enum ColoredShadow { case money, pain, warn }

    private func installGradient(colors: [CGColor], locations: [NSNumber]) {
        let gradient = CAGradientLayer()
        gradient.colors = colors
        gradient.locations = locations
        gradient.startPoint = SPSupport.gradientStart
        gradient.endPoint = SPSupport.gradientEnd
        gradient.cornerRadius = cardCornerRadius
        layer.insertSublayer(gradient, at: 0)
        gradientLayer = gradient
    }

    private func refreshDynamicColors() {
        // Re-resolve the same recipe that `applyTone()` first installed.
        switch tone {
        case .surface:
            applyHairlineStrokeIfLight()
            applyShadow1()
        case .raised:
            applyRaisedHairlineIfLight()
            applyShadow1()
        case .outline:
            applyOutlineStroke()
        case .money:
            applyColoredShadow(.money)
        case .pain:
            applyColoredShadow(.pain)
        case .warn:
            applyColoredShadow(.warn)
        }
    }
}
