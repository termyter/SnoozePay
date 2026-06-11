import UIKit

/// Big snooze CTA — `.sp-snooze` in `components.css`.
///
/// Visual hierarchy: the price is the dominant element (32pt mono bold),
/// with a small caps top label ("Поспать ещё 5 мин") and an optional
/// hint meta line. Tone selects between the warn (default snooze price)
/// and pain (progressive / expensive snooze) gradients.
///
/// Min height 80pt so the touch target reads as a primary action even on
/// the smallest device. Press scale 0.97 — unified with SPButton +
/// SPAmountPreset so the whole design system pulses by the same delta.
final class SPSnoozePrice: UIControl {

    enum Tone: Equatable {
        case warn   // Default snooze — warm amber gradient
        case pain   // Progressive / expensive — pain coral gradient
        /// Progressive escalation — interpolates linearly between the warn
        /// and pain gradients. `intensity` is clamped to `0...1`; 0 renders
        /// pure warn (snooze #1), 1 renders pure pain (snooze #6+). The
        /// shadow tint blends the same way so the surrounding glow tracks
        /// the fill colour as the user keeps snoozing.
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
    ///   - hint: Optional secondary line ("Уже 3-я задержка" etc).
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

    // MARK: - Public API

    func update(price: Decimal, minutes: Int? = nil, hint: String? = nil) {
        self.price = price
        if let minutes = minutes { self.minutes = minutes }
        self.hint = hint
        capsLabel.attributedText = NSAttributedString(
            string: "Поспать ещё \(self.minutes) мин".uppercased(),
            attributes: [
                .font: AppTypography.caps,
                .kern: 12 * 0.14,
                .foregroundColor: foreground.withAlphaComponent(0.82)
            ]
        )
        priceLabel.attributedText = MoneyFormatter.attributed(
            price, digitsFont: AppTypography.moneyLg, prefix: "−"
        )
        if let hint = hint {
            hintLabel.text = hint
            hintLabel.isHidden = false
        } else {
            hintLabel.isHidden = true
        }
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
        capsLabel.attributedText = NSAttributedString(
            string: "Поспать ещё \(self.minutes) мин".uppercased(),
            attributes: [
                .font: AppTypography.caps,
                .kern: 12 * 0.14,
                .foregroundColor: foreground.withAlphaComponent(0.82)
            ]
        )
    }

    // MARK: - Configuration

    private func configure() {
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
        case .progressive(let intensity):
            // Cross-fade the on-fill text colour the same way the gradient
            // is interpolated. At intensity 0 the surface is pure amber so
            // we want the warn ink (near-black); at intensity 1 it's coral
            // and the pain ink (white) gives 4.5:1 contrast.
            let clamped = max(0.0, min(1.0, intensity))
            return SPSupport.lerpColor(
                AppColors.fgOnWarn,
                AppColors.fgOnPain,
                progress: clamped
            )
        }
    }

    private func applyTone() {
        gradientLayer?.removeFromSuperlayer()
        let gradient = CAGradientLayer()
        gradient.startPoint = SPSupport.gradientStart
        gradient.endPoint = SPSupport.gradientEnd
        gradient.cornerRadius = AppRadius.xl
        switch tone {
        case .warn:
            gradient.colors = SPSupport.warnGradientColors
            gradient.locations = SPSupport.warnGradientLocations
            layer.shadowColor = AppColors.warn500.cgColor
        case .pain:
            gradient.colors = SPSupport.painGradientColors
            gradient.locations = SPSupport.painGradientLocations
            layer.shadowColor = AppColors.pain500.cgColor
        case .progressive(let intensity):
            let clamped = max(0.0, min(1.0, intensity))
            gradient.colors = SPSupport.progressiveGradientColors(intensity: clamped)
            gradient.locations = SPSupport.warnGradientLocations
            layer.shadowColor = SPSupport.lerpColor(
                AppColors.warn500,
                AppColors.pain500,
                progress: clamped
            ).cgColor
        }
        layer.insertSublayer(gradient, at: 0)
        gradientLayer = gradient
        layer.shadowOpacity = 0.40
        layer.shadowOffset = CGSize(width: 0, height: 8)
        layer.shadowRadius = 22
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
