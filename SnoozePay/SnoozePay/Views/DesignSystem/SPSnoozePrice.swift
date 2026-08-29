import UIKit

/// Big snooze CTA — `.sp-snooze` in `components.css`.
///
/// Visual hierarchy: the price is the dominant element (32pt mono bold),
/// with a small caps top label (a 14pt clock glyph + «Спать ещё 5 мин»)
/// and an optional hint meta line. Tone selects between the warn (default
/// snooze price) and pain (progressive / expensive snooze) gradients.
///
/// Per `SPDawnV3.jsx:82-85` the CTA stays GOLD (`.warn`) on every progressive
/// step — escalation is signalled by the background tone crossfade + the
/// indicator pill, never by reddening the button itself. The legacy
/// `.progressive` tone is kept for back-compat but now resolves to the warn
/// surface so callers can pass it without re-tinting the button.
///
/// Min height 80pt so the touch target reads as a primary action even on
/// the smallest device. Press scale 0.97 — unified with SPButton +
/// SPAmountPreset so the whole design system pulses by the same delta.
final class SPSnoozePrice: UIControl {

    enum Tone: Equatable {
        case warn   // Default snooze — warm amber gradient
        case pain   // Progressive / expensive — pain coral gradient
        /// Progressive escalation. Historically interpolated the warn → pain
        /// gradient by `intensity`; per `SPDawnV3.jsx:153-155` the CTA must
        /// stay gold across all steps, so this now renders the warn surface
        /// regardless of `intensity`. The case is retained so the firing flow
        /// can keep passing it without a call-site rewrite.
        case progressive(intensity: Double)
    }

    // MARK: - Configuration

    private(set) var tone: Tone
    private(set) var price: Decimal
    private(set) var minutes: Int
    private(set) var hint: String?

    var onTap: (() -> Void)?

    // MARK: - State

    override var isEnabled: Bool {
        didSet { refreshDisabledAppearance() }
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(
                withDuration: SPSupport.durationQuick,
                delay: 0,
                options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut],
                animations: {
                    self.transform = self.isHighlighted
                        ? CGAffineTransform(scaleX: 0.97, y: 0.97)
                        : .identity
                },
                completion: nil
            )
        }
    }

    // MARK: - Subviews

    private let capsLabel = UILabel()
    private let priceLabel = UILabel()
    private let hintLabel = UILabel()
    private var gradientLayer: CAGradientLayer?

    // MARK: - Init

    /// - Parameters:
    ///   - price: Cost of the snooze in roubles.
    ///   - minutes: Snooze duration, displayed in the caps line. Defaults
    ///     to 5 (the standard SnoozePay window).
    ///   - tone: `.warn` or `.pain`.
    ///   - hint: Optional secondary line («Уже 3-я задержка» etc).
    ///   - onTap: Tap callback.
    init(
        price: Decimal,
        minutes: Int = 5,
        tone: Tone = .warn,
        hint: String? = nil,
        onTap: (() -> Void)? = nil
    ) {
        self.price = price
        self.minutes = minutes
        self.tone = tone
        self.hint = hint
        self.onTap = onTap
        super.init(frame: .zero)
        configure()
        update(price: price, minutes: minutes, hint: hint)
        addTarget(self, action: #selector(handleTap), for: .touchUpInside)
        // Expose as a SINGLE accessibility button rather than its internal
        // caps/price/hint labels — VoiceOver reads one control, and UI tests
        // can target it via `accessibilityIdentifier`. The label is refreshed
        // in `update(price:…)` so it tracks the live minutes value.
        isAccessibilityElement = true
        accessibilityTraits = .button
        // iOS 17 deprecated `traitCollectionDidChange(_:)` — register a
        // closure-based observer when available; the legacy override below
        // stays as a fallback for older runtimes.
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: SPSnoozePrice, _) in
                view.refreshGradientColors()
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer?.frame = bounds
        layer.shadowPath = UIBezierPath(
            roundedRect: bounds,
            cornerRadius: AppRadius.xl
        ).cgPath
    }

    @available(iOS, deprecated: 17.0, message: "Replaced by registerForTraitChanges; kept for iOS 15/16.")
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        // iOS 17+ runtimes get the same callback through the registered
        // observer (see init); skip here so we don't refresh twice.
        if #available(iOS 17.0, *) { return }
        refreshGradientColors()
    }

    // MARK: - Public API

    func update(price: Decimal, minutes: Int? = nil, hint: String? = nil) {
        self.price = price
        if let minutes = minutes { self.minutes = minutes }
        self.hint = hint
        capsLabel.attributedText = makeCapsText()
        priceLabel.attributedText = MoneyFormatter.attributed(
            price, digitsFont: AppTypography.moneyLg, prefix: "−"
        )
        if let hint = hint {
            hintLabel.text = hint
            hintLabel.isHidden = false
        } else {
            hintLabel.isHidden = true
        }
        accessibilityLabel = Localized.format("firing.snooze.accessibility", self.minutes)
        accessibilityValue = MoneyFormatter.string(price)
    }

    /// Re-tone the surface in place. Used by the progressive-firing flow
    /// (#139) to bump the snooze CTA's redness as `snoozeCount` grows
    /// without rebuilding the control.
    func setTone(_ newTone: Tone) {
        guard tone != newTone else { return }
        tone = newTone
        applyTone()
        priceLabel.textColor = foreground
        hintLabel.textColor = foreground
        // Re-render the caps label so its tinted attributedString picks up
        // the new foreground.
        capsLabel.attributedText = makeCapsText()
    }

    /// Build the caps line — a 14pt leading clock glyph followed by
    /// «СПАТЬ ЕЩЁ N МИН» (`SPDawnV3.jsx:82-85`). The glyph rides the text
    /// baseline as an `NSTextAttachment` tinted to the current foreground.
    private func makeCapsText() -> NSAttributedString {
        let ink = foreground.withAlphaComponent(0.82)
        let result = NSMutableAttributedString()
        if let glyph = UIImage(systemName: "clock")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold))
            .withTintColor(ink, renderingMode: .alwaysOriginal) {
            let attachment = NSTextAttachment(image: glyph)
            // Nudge the glyph down a touch so it optically centres on the caps
            // cap-height rather than the ascender.
            attachment.bounds = CGRect(x: 0, y: -2, width: 14, height: 14)
            result.append(NSAttributedString(attachment: attachment))
            result.append(NSAttributedString(string: "  "))
        }
        result.append(NSAttributedString(
            string: Localized.format("firing.snooze.caps", minutes).uppercased(),
            attributes: [
                .font: AppTypography.caps,
                .kern: 12 * 0.14,
                .foregroundColor: ink
            ]
        ))
        return result
    }

    // MARK: - Configuration

    private func configure() {
        // Owns its autoresizing flag. This view activates a required
        // `heightAnchor` on ITSELF (below), which cannot coexist with the
        // constraints UIKit synthesises from the `.zero` frame it is born
        // with. A caller who forgets the reset gets no error: the engine pays
        // for the collision out of whatever else is breakable, which in #467
        // was the intrinsic height of the SIBLINGS — they kept their
        // x/y/width and measured 0 tall, and the screen read as blank.
        //
        // Quieter here than in `SPButton`'s `==` case: an unsatisfiable `>=`
        // need not print "Unable to simultaneously satisfy constraints" at
        // all, so the collapsed neighbour is the only symptom. Owning the flag
        // makes forgetting impossible; call sites that still set it are
        // harmlessly redundant (#584).
        translatesAutoresizingMaskIntoConstraints = false

        layer.cornerRadius = AppRadius.xl
        layer.masksToBounds = false

        capsLabel.translatesAutoresizingMaskIntoConstraints = false
        capsLabel.textAlignment = .center

        priceLabel.translatesAutoresizingMaskIntoConstraints = false
        priceLabel.font = AppTypography.moneyLg
        priceLabel.textAlignment = .center
        priceLabel.textColor = foreground

        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.font = AppTypography.meta
        hintLabel.textAlignment = .center
        hintLabel.alpha = 0.85
        hintLabel.textColor = foreground

        let stack = UIStackView(arrangedSubviews: [capsLabel, priceLabel, hintLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 4
        stack.isUserInteractionEnabled = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 80),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -22),
            // `.sp-snooze` padding 18px 20px 22px (design v3 tightened 24 → 20).
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20)
        ])

        applyTone()
    }

    private var foreground: UIColor {
        switch tone {
        case .warn: return AppColors.fgOnWarn
        case .pain: return AppColors.fgOnPain
        // The CTA stays gold across all progressive steps (`SPDawnV3.jsx:
        // 153-155`), so the on-fill ink is always the warn ink.
        case .progressive: return AppColors.fgOnWarn
        }
    }

    private func applyTone() {
        gradientLayer?.removeFromSuperlayer()
        let gradient = CAGradientLayer()
        gradient.startPoint = SPSupport.gradientStart
        gradient.endPoint = SPSupport.gradientEnd
        gradient.cornerRadius = AppRadius.xl
        gradient.locations = toneGradientLocations
        gradient.colors = toneGradientColors
        layer.insertSublayer(gradient, at: 0)
        gradientLayer = gradient
        applyToneShadowColor()
        layer.shadowOpacity = 0.40
        layer.shadowOffset = CGSize(width: 0, height: 8)
        layer.shadowRadius = 22
    }

    /// Ramp for the current tone, resolved against THIS control's traits.
    ///
    /// `.progressive` renders the warn surface on every step — the CTA stays
    /// gold and escalation is signalled by the background, per
    /// `SPDawnV3.jsx:153-155`.
    private var toneGradientColors: [CGColor] {
        switch tone {
        case .pain: return SPSupport.painGradientColors(for: traitCollection)
        case .warn, .progressive: return SPSupport.warnGradientColors(for: traitCollection)
        }
    }

    private var toneGradientLocations: [NSNumber] {
        switch tone {
        case .pain: return SPSupport.painGradientLocations
        case .warn, .progressive: return SPSupport.warnGradientLocations
        }
    }

    private func applyToneShadowColor() {
        let token: UIColor
        switch tone {
        case .pain: token = AppColors.pain500
        case .warn, .progressive: token = AppColors.warnFill500
        }
        layer.shadowColor = token.resolvedColor(with: traitCollection).cgColor
    }

    /// Re-tint the fill in place on a theme flip.
    ///
    /// `CAGradientLayer.colors` holds plain `CGColor`s that never re-resolve.
    /// `AlarmFiringViewController` pins its whole scene dark, but this control
    /// is *built* before it joins that hierarchy, so without a refresh a
    /// light-theme app painted the bronze light warn ramp onto the dark firing
    /// scene and kept it there. Re-tinting rather than re-installing keeps the
    /// layer frame that `layoutSubviews` owns.
    private func refreshGradientColors() {
        gradientLayer?.colors = toneGradientColors
        gradientLayer?.locations = toneGradientLocations
        applyToneShadowColor()
    }

    private func refreshDisabledAppearance() {
        alpha = isEnabled ? 1.0 : 0.35
        layer.shadowOpacity = isEnabled ? 0.40 : 0.0
    }

    @objc
    private func handleTap() {
        onTap?()
    }
}
