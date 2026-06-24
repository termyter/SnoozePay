import UIKit

/// Top-up amount preset tile — `.sp-preset` in `components.css`.
///
/// Visual: outlined card (1.5pt `stroke1`) with a centered mono amount
/// (700 18pt mono per `.sp-preset__value`) and an optional secondary label
/// (`meta` 13pt). When `selected` is true the border switches to `money400`,
/// the fill takes a 10% money tint, and a 4pt outer glow ring renders. A
/// "Популярно" badge with the money gradient fill floats above the top edge
/// when `popular` is true.
final class SPAmountPreset: UIControl {

    /// `.sp-preset__value { font: 700 18px/22px var(--sp-font-mono) }`.
    private static var valueFont: UIFont { AppFonts.mono(.bold, 18) }

    // MARK: - State

    private(set) var value: Decimal
    private(set) var label: String?
    private(set) var popular: Bool

    /// Toggling sliding fades the card between idle and selected appearance.
    /// Setter animates by default; pass `setSelected(_:animated:)` for
    /// instant toggles.
    override var isSelected: Bool {
        didSet { applySelectionState(animated: oldValue != isSelected) }
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: SPSupport.durationQuick) {
                self.transform = self.isHighlighted
                    ? CGAffineTransform(translationX: 0, y: -1)
                    : .identity
            }
        }
    }

    var onTap: (() -> Void)?

    // MARK: - Subviews

    private let valueLabel = UILabel()
    private let labelView = UILabel()
    private let popularBadge = InsetLabel(insets: UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10))
    /// Money-gradient backing for the «Популярно» badge (`.sp-preset__pop`
    /// fills with `--sp-grad-money`). Lives in `popularBackground` *behind* the
    /// label — a `UILabel` draws its text as the layer's own content, which
    /// composites below any sublayer, so a gradient inserted into the label's
    /// own layer painted over the text (badge showed an empty green pill).
    private let popularBackground = UIView()
    private let popularGradient = CAGradientLayer()
    private let stack = UIStackView()

    // MARK: - Init

    /// - Parameters:
    ///   - value: Top-up amount (rendered with `formattedRubles()`).
    ///   - label: Optional second line ("Бонус 5%", "Минимум", ...).
    ///   - selected: Initial selection state.
    ///   - popular: Show the "Популярно" badge above the top edge.
    ///   - onTap: Tap callback.
    init(
        value: Decimal,
        label: String? = nil,
        selected: Bool = false,
        popular: Bool = false,
        onTap: (() -> Void)? = nil
    ) {
        self.value = value
        self.label = label
        self.popular = popular
        self.onTap = onTap
        super.init(frame: .zero)
        configure()
        update(value: value, label: label)
        isSelected = selected
        applySelectionState(animated: false)
        popularBadge.isHidden = !popular
        popularBackground.isHidden = !popular
        addTarget(self, action: #selector(handleTap), for: .touchUpInside)
        // iOS 17 deprecated `traitCollectionDidChange(_:)` — register a
        // closure-based observer when available; the legacy override below
        // stays as a fallback for older runtimes.
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: SPAmountPreset, _) in
                view.applySelectionState(animated: false)
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = AppRadius.md     // 16pt — matches sp-r-md
        // Outer ring is faked via shadow when selected — pre-rasterise the
        // path so it tracks the rounded corners cleanly.
        layer.shadowPath = UIBezierPath(
            roundedRect: bounds,
            cornerRadius: AppRadius.md
        ).cgPath
        // Keep the «Популярно» gradient backing matched to its backing view.
        popularGradient.frame = popularBackground.bounds
    }

    @available(iOS, deprecated: 17.0, message: "Replaced by registerForTraitChanges; kept for iOS 15/16.")
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        // iOS 17+ runtimes get the refresh through the registered observer
        // (see init); skip here so we don't refresh twice.
        if #available(iOS 17.0, *) { return }
        applySelectionState(animated: false)
    }

    // MARK: - Public API

    func update(value: Decimal, label: String?) {
        self.value = value
        self.label = label
        valueLabel.attributedText = MoneyFormatter.attributed(
            value, digitsFont: Self.valueFont
        )
        if let label = label {
            labelView.text = label
            labelView.isHidden = false
        } else {
            labelView.isHidden = true
        }
    }

    // MARK: - Configuration

    private func configure() {
        backgroundColor = AppColors.bg1
        layer.cornerRadius = AppRadius.md
        layer.masksToBounds = false
        layer.borderWidth = 1.5

        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.font = Self.valueFont
        valueLabel.textColor = AppColors.fg1
        valueLabel.textAlignment = .center

        labelView.translatesAutoresizingMaskIntoConstraints = false
        labelView.font = AppTypography.meta
        labelView.textColor = AppColors.fg3
        labelView.textAlignment = .center
        // The "≈ N откладываний" hint is too wide for a 3-column tile on one
        // line (it truncated to "≈ 1 откладыва…"). Wrap to two lines and let
        // the font shrink a touch as a backstop so the full word is always
        // visible regardless of count/plural form.
        labelView.numberOfLines = 2
        labelView.adjustsFontSizeToFitWidth = true
        labelView.minimumScaleFactor = 0.8

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 4
        stack.isUserInteractionEnabled = false
        stack.addArrangedSubview(valueLabel)
        stack.addArrangedSubview(labelView)
        addSubview(stack)

        // Popular badge — small caps pill that floats above the top edge.
        // `.sp-preset__pop` uses mixed-case «Популярно», the money gradient
        // fill, and `3px 10px` padding (no fixed width — it hugs its text).
        popularBadge.translatesAutoresizingMaskIntoConstraints = false
        popularBadge.attributedText = NSAttributedString(
            string: "Популярно",
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: AppColors.fgOnMoney
            ]
        )
        popularBadge.textAlignment = .center
        popularBadge.backgroundColor = .clear

        // Gradient backing view — sits strictly *behind* the label so the text
        // composites on top (see `popularBackground` doc). The label keeps a
        // clear background and hugs its text via `InsetLabel`'s 10pt insets;
        // the backing is pinned to the label's bounds.
        popularBackground.translatesAutoresizingMaskIntoConstraints = false
        popularBackground.isUserInteractionEnabled = false
        popularGradient.colors = SPSupport.moneyGradientColors
        popularGradient.locations = SPSupport.moneyGradientLocations
        popularGradient.startPoint = SPSupport.gradientStart
        popularGradient.endPoint = SPSupport.gradientEnd
        popularGradient.cornerRadius = 11
        popularBackground.layer.insertSublayer(popularGradient, at: 0)
        popularBackground.layer.cornerRadius = 11
        popularBackground.layer.masksToBounds = true
        addSubview(popularBackground)
        addSubview(popularBadge)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 88),
            // `.sp-preset` padding 16px 16px (design v3; was 18px 12px).
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            popularBadge.centerXAnchor.constraint(equalTo: centerXAnchor),
            popularBadge.centerYAnchor.constraint(equalTo: topAnchor),
            popularBadge.heightAnchor.constraint(equalToConstant: 22),

            popularBackground.leadingAnchor.constraint(equalTo: popularBadge.leadingAnchor),
            popularBackground.trailingAnchor.constraint(equalTo: popularBadge.trailingAnchor),
            popularBackground.topAnchor.constraint(equalTo: popularBadge.topAnchor),
            popularBackground.bottomAnchor.constraint(equalTo: popularBadge.bottomAnchor)
        ])
    }

    private func applySelectionState(animated: Bool) {
        let apply: () -> Void = {
            if self.isSelected {
                // `.sp-preset.is-selected` tints with money400 (`#2EDB9F` —
                // `rgba(46,219,159,…)`), a hair brighter than money500, so the
                // selected fill/ring pop against the surface.
                self.backgroundColor = AppColors.money400.withAlphaComponent(0.10)
                self.layer.borderColor = AppColors.money400.cgColor
                // Tight selection ring: 4pt radius / 0.10 opacity reads as a
                // crisp brand outline rather than a diffuse glow that bled
                // into adjacent presets at radius 8 / opacity 0.18.
                self.layer.shadowColor = AppColors.money400.cgColor
                self.layer.shadowOpacity = 0.10
                self.layer.shadowOffset = .zero
                self.layer.shadowRadius = 4
                self.layer.masksToBounds = false
            } else {
                self.backgroundColor = AppColors.bg1
                self.layer.borderColor = AppColors.stroke1
                    .resolvedColor(with: self.traitCollection).cgColor
                self.layer.shadowOpacity = 0
            }
        }
        if animated {
            UIView.animate(withDuration: SPSupport.durationQuick, animations: apply)
        } else {
            apply()
        }
    }

    @objc
    private func handleTap() {
        onTap?()
    }
}

/// `UILabel` that pads its text content — used for the «Популярно» badge so it
/// hugs its (mixed-case) text plus a 10pt horizontal inset rather than relying
/// on a fixed width.
private final class InsetLabel: UILabel {

    private let insets: UIEdgeInsets

    init(insets: UIEdgeInsets) {
        self.insets = insets
        super.init(frame: .zero)
        textAlignment = .center
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let base = super.intrinsicContentSize
        return CGSize(
            width: base.width + insets.left + insets.right,
            height: base.height + insets.top + insets.bottom
        )
    }
}
