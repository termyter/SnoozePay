import UIKit

/// Hero balance card — `.sp-balance` in `components.css`.
///
/// Visual: 28pt vertical / 24pt horizontal padding, `bg2` fill with a soft
/// money-tinted radial highlight in the top-right corner. Caps "Баланс"
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
    private let valueLabel = UILabel()
    private let valueGradient = CAGradientLayer()
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
    ///     such as "обновлено 2 ч назад" or "ближайшее списание завтра".
    init(balance: Decimal, delta: Decimal? = nil, hint: String? = nil) {
        self.balance = balance
        self.delta = delta
        self.hint = hint
        super.init(frame: .zero)
        configure()
        update(balance: balance, delta: delta, hint: hint)
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
        // Re-mask the gradient with the freshly laid-out glyph rect so the
        // gradient still tracks the digit baseline after font metrics
        // resolve.
        applyValueGradient()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        radialOverlay.setNeedsDisplay()
    }

    // MARK: - Public API

    /// Update card data in-place. Cheaper than rebuilding the view when the
    /// balance updates — the same labels are reused so the gradient mask
    /// re-rasterises only when the layout cycle invalidates.
    func update(balance: Decimal, delta: Decimal? = nil, hint: String? = nil) {
        self.balance = balance
        self.delta = delta
        self.hint = hint
        valueLabel.text = balance.formattedRubles()
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
        layer.masksToBounds = true   // radial overlay clips inside corners

        radialOverlay.translatesAutoresizingMaskIntoConstraints = false
        addSubview(radialOverlay)

        capsLabel.translatesAutoresizingMaskIntoConstraints = false
        capsLabel.attributedText = NSAttributedString(
            string: "БАЛАНС",
            attributes: [
                .font: AppTypography.caps,
                .kern: 12 * 0.12,
                .foregroundColor: AppColors.fg3
            ]
        )

        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        // Hero balance uses `moneyXl` (56pt mono bold) per `tokens.css` L168
        // — `--sp-t-money-xl: 700 56px/60px var(--sp-font-mono)`. The bigger
        // glyphs can overflow on narrow devices for large balances
        // ("1 234 567 ₽"), so we let UIKit shrink to 75% before clipping.
        valueLabel.font = AppTypography.moneyXl
        // Set a neutral text colour as a safety net — `applyValueGradient`
        // promotes this to a gradient mask once layout resolves.
        valueLabel.textColor = AppColors.fg1
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
        stack.spacing = 4
        stack.setCustomSpacing(8, after: capsLabel)
        stack.setCustomSpacing(14, after: deltaLabel)
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 28),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -28),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24)
        ])

        // Add the gradient layer above the label so the mask can clip it.
        valueGradient.colors = SPSupport.moneyGradientColors
        valueGradient.locations = SPSupport.moneyGradientLocations
        valueGradient.startPoint = SPSupport.gradientStart
        valueGradient.endPoint = SPSupport.gradientEnd
    }

    private func applyValueGradient() {
        // Position the gradient over the label and mask it to the rendered
        // text — this is the CALayer equivalent of CSS's
        // `-webkit-background-clip: text`. We add the gradient as a
        // sublayer of the label's layer rather than rasterising into the
        // label so size / theme switches refresh cheaply.
        let textBounds = valueLabel.bounds
        guard textBounds.width > 0, textBounds.height > 0 else { return }
        if valueGradient.superlayer !== valueLabel.layer {
            valueLabel.layer.addSublayer(valueGradient)
        }
        valueGradient.frame = textBounds

        // Mask the gradient to the text shape — re-render every layout pass
        // so font / weight / size changes refresh.
        let renderer = UIGraphicsImageRenderer(size: textBounds.size)
        let mask = renderer.image { ctx in
            ctx.cgContext.setFillColor(UIColor.white.cgColor)
            (valueLabel.text ?? "").draw(
                in: textBounds,
                withAttributes: [
                    .font: valueLabel.font as Any,
                    .foregroundColor: UIColor.white
                ]
            )
        }
        let maskLayer = CALayer()
        maskLayer.frame = textBounds
        maskLayer.contents = mask.cgImage
        valueGradient.mask = maskLayer
        // Hide the underlying label colour so we don't double-stack glyph
        // outlines (label paints fg1, gradient paints money tones).
        valueLabel.textColor = .clear
    }

    private func renderDelta(_ delta: Decimal) -> NSAttributedString {
        let arrow = delta < 0 ? "↓" : "↑"
        let abs = NSDecimalNumber(decimal: delta < 0 ? -delta : delta).decimalValue
        let str = "\(arrow) \(abs.formattedRubles()) за неделю"
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
        let colors = [
            AppColors.money400.withAlphaComponent(0.18).cgColor,
            UIColor.clear.cgColor
        ]
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
    func formattedRubles() -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.maximumFractionDigits = 0
        formatter.roundingMode = .down
        let number = NSDecimalNumber(decimal: self)
        let text = formatter.string(from: number) ?? "\(number.intValue)"
        return "\(text) ₽"
    }
}
