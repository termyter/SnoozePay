import UIKit

/// Top-up amount preset tile — `.sp-preset` in `components.css`.
///
/// Visual: outlined card (1.5pt `stroke1`) with a centered mono amount
/// (700 18pt mono per `.sp-preset__value`) and an optional secondary label
/// (`meta` 13pt). When `selected` is true the border switches to `money400`,
/// the fill takes a 10% money tint, and a 4pt outer glow ring renders. A
/// "Популярно" badge floats above the top edge when `popular` is true.
///
/// Light theme: `bg1` is pure white and the page under the tile is `bg0`
/// (`#F4F6FB`) — about 4% of luminance apart. The hairline alone reads as a
/// flat table cell and a shadow alone doesn't separate white from near-white,
/// so the idle tile gets `--sp-shadow-1` *and* the border in light mode. Dark
/// mode is the canon and stays flat.
final class SPAmountPreset: UIControl {

    /// `.sp-preset__value { font: 700 18px/22px var(--sp-font-mono) }`.
    private static var valueFont: UIFont { AppFonts.mono(.bold, 18) }

    // MARK: - Tokens & metrics
    //
    // Exposed so `SPDesignSystemLightThemeTests` measures the colours the badge
    // actually renders rather than a copy of them.

    /// «Популярно» badge fill. A **solid** `money500`, not `--sp-grad-money`.
    ///
    /// The gradient version could not carry a single ink in the dark theme:
    /// its stops run `money400 → money700`, and 12pt bold caps measure
    /// 1.79:1 in white on the `#2EDB9F` end versus 3.20:1 in `fgOnMoney` ink
    /// on the `#0B7A56` end. Whichever ink you pick, one half of an 90×22
    /// pill fails. A solid `money500` clears 6.7:1 (dark) / 7.0:1 (light) —
    /// `SPDesignSystemLightThemeTests` pins both.
    static let popularBadgeFill = AppColors.money500
    /// Ink on `popularBadgeFill` — dark mint on the bright dark-theme fill,
    /// white on the light theme's dark-green fill.
    static let popularBadgeInk = AppColors.fgOnMoney

    /// `.sp-preset__pop` badge height; the corner radius is half of it so the
    /// pill stays fully rounded.
    private static let popularBadgeHeight: CGFloat = 22
    /// `.sp-preset__pop { padding: 3px 10px }` — off the 4pt grid on purpose,
    /// it is optical padding around caps text, not layout rhythm.
    private static let popularBadgeHorizontalInset: CGFloat = 10
    /// `.sp-preset { min-height: 88px }`.
    private static let minimumHeight: CGFloat = 88
    /// `.sp-preset` outline weight.
    private static let borderWidth: CGFloat = 1.5

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
    private let popularBadge = InsetLabel(
        insets: UIEdgeInsets(
            top: 0,
            left: SPAmountPreset.popularBadgeHorizontalInset,
            bottom: 0,
            right: SPAmountPreset.popularBadgeHorizontalInset
        )
    )
    /// Fill backing for the «Популярно» badge. Lives *behind* the label — a
    /// `UILabel` draws its text as the layer's own content, which composites
    /// below any sublayer, so a fill inserted into the label's own layer
    /// painted over the text (the badge showed as an empty green pill).
    private let popularBackground = UIView()
    private let stack = UIStackView()
    /// Tile outline drawn as a *sublayer* rather than `layer.borderWidth`: a
    /// CALayer border renders above all sublayers, so the real border painted
    /// a line straight across the «Популярно» badge that floats on the top
    /// edge. As a sublayer (inserted below the badge) the badge covers it.
    private let borderLayer = CALayer()

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
        borderLayer.frame = bounds
        borderLayer.cornerRadius = AppRadius.md
        // The outer ring (selected) and `--sp-shadow-1` (idle, light theme)
        // both render through `layer.shadow*` — pre-rasterise the path so
        // either one tracks the rounded corners cleanly.
        layer.shadowPath = UIBezierPath(
            roundedRect: bounds,
            cornerRadius: AppRadius.md
        ).cgPath
        // The ambient stop of `--sp-shadow-1` is a sublayer whose frame has to
        // follow the tile, so re-install it once geometry has settled.
        if !isSelected {
            applyIdleElevation()
        }
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

        backgroundColor = AppColors.bg1
        layer.cornerRadius = AppRadius.md
        layer.masksToBounds = false
        // Border as a bottom sublayer (not `layer.borderWidth`) so it draws
        // *below* the badge — see `borderLayer`.
        borderLayer.borderWidth = Self.borderWidth
        layer.insertSublayer(borderLayer, at: 0)

        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.font = Self.valueFont
        valueLabel.textColor = AppColors.fg1
        valueLabel.textAlignment = .center

        labelView.translatesAutoresizingMaskIntoConstraints = false
        labelView.font = AppTypography.meta
        labelView.textColor = AppColors.fg3
        labelView.textAlignment = .center
        // The "≈ N откладываний" hint is too wide for a 3-column tile (it
        // truncated to "≈ 1 откладыва…"). Keep it on a single line and shrink
        // the font as a backstop so the full word is always visible regardless
        // of count/plural form. `adjustsFontSizeToFitWidth` is honoured only for
        // single-line labels — pairing it with numberOfLines=2 silently disabled
        // the shrink and let the longest form ellipsise.
        labelView.numberOfLines = 1
        labelView.adjustsFontSizeToFitWidth = true
        labelView.minimumScaleFactor = 0.7

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = AppSpacing.sp1
        stack.isUserInteractionEnabled = false
        stack.addArrangedSubview(valueLabel)
        stack.addArrangedSubview(labelView)
        addSubview(stack)

        configurePopularBadge()

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: Self.minimumHeight),
            // `.sp-preset` padding 16px 16px (design v3; was 18px 12px).
            stack.topAnchor.constraint(equalTo: topAnchor, constant: AppSpacing.sp4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -AppSpacing.sp4),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: AppSpacing.sp4),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -AppSpacing.sp4),

            popularBadge.centerXAnchor.constraint(equalTo: centerXAnchor),
            popularBadge.centerYAnchor.constraint(equalTo: topAnchor),
            popularBadge.heightAnchor.constraint(equalToConstant: Self.popularBadgeHeight),

            popularBackground.leadingAnchor.constraint(equalTo: popularBadge.leadingAnchor),
            popularBackground.trailingAnchor.constraint(equalTo: popularBadge.trailingAnchor),
            popularBackground.topAnchor.constraint(equalTo: popularBadge.topAnchor),
            popularBackground.bottomAnchor.constraint(equalTo: popularBadge.bottomAnchor)
        ])
    }

    /// Small caps pill that floats above the top edge. `.sp-preset__pop` uses
    /// mixed-case «Популярно» and `3px 10px` padding — no fixed width, it hugs
    /// its own text.
    private func configurePopularBadge() {
        popularBadge.translatesAutoresizingMaskIntoConstraints = false
        popularBadge.attributedText = NSAttributedString(
            string: "Популярно",
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                // `fgOnMoney` is defined as ink on a SOLID money fill, which is
                // exactly what `popularBadgeFill` now is — see its doc for why
                // the gradient had to go.
                .foregroundColor: Self.popularBadgeInk
            ]
        )
        popularBadge.textAlignment = .center
        popularBadge.backgroundColor = .clear

        // Fill backing view — sits strictly *behind* the label so the text
        // composites on top (see `popularBackground` doc). The label keeps a
        // clear background and hugs its text via `InsetLabel`'s insets; the
        // backing is pinned to the label's bounds.
        popularBackground.translatesAutoresizingMaskIntoConstraints = false
        popularBackground.isUserInteractionEnabled = false
        popularBackground.backgroundColor = Self.popularBadgeFill
        popularBackground.layer.cornerRadius = Self.popularBadgeHeight / 2
        popularBackground.layer.masksToBounds = true
        addSubview(popularBackground)
        addSubview(popularBadge)
    }

    private func applySelectionState(animated: Bool) {
        let apply: () -> Void = {
            if self.isSelected {
                // `.sp-preset.is-selected` tints with money400 — a hair
                // brighter than money500 on dark, a step lighter than it on
                // light — so the selected fill/ring pop against the surface.
                //
                // `.cgColor` on a dynamic token snapshots whatever
                // `UITraitCollection.current` happens to be, which inside a
                // view method is not necessarily this view's trait collection.
                // Resolve explicitly, as the idle branch already did.
                let accent = AppColors.money400.resolvedColor(with: self.traitCollection)
                self.backgroundColor = accent.withAlphaComponent(0.10)
                self.borderLayer.borderColor = accent.cgColor
                // Tight selection ring: 4pt radius / 0.10 opacity reads as a
                // crisp brand outline rather than a diffuse glow that bled
                // into adjacent presets at radius 8 / opacity 0.18.
                self.layer.shadowColor = accent.cgColor
                self.layer.shadowOpacity = 0.10
                self.layer.shadowOffset = .zero
                self.layer.shadowRadius = 4
                self.layer.masksToBounds = false
                self.removeAmbientShadowLayer()
            } else {
                self.backgroundColor = AppColors.bg1
                self.borderLayer.borderColor = AppColors.stroke1
                    .resolvedColor(with: self.traitCollection).cgColor
                self.applyIdleElevation()
            }
        }
        if animated {
            UIView.animate(withDuration: SPSupport.durationQuick, animations: apply)
        } else {
            apply()
        }
    }

    /// Idle-tile elevation.
    ///
    /// Dark keeps the flat outlined card of the canon: `bg1` (`#0E1320`) on
    /// `bg0` (`#060912`) is a visible surface step and the hairline finishes
    /// it. Light has `bg1` = `#FFFFFF` on `bg0` = `#F4F6FB` — a shadow alone
    /// cannot separate white from near-white, and a border alone reads as a
    /// flat table cell, so the tile gets both.
    private func applyIdleElevation() {
        layer.masksToBounds = false
        guard traitCollection.userInterfaceStyle != .dark else {
            layer.shadowOpacity = 0
            removeAmbientShadowLayer()
            return
        }
        AppShadow.shadow1(for: traitCollection).apply(to: layer)
        AppShadow.installAmbientShadow1Layer(
            on: layer,
            cornerRadius: AppRadius.md,
            trait: traitCollection
        )
    }

    /// Drop the ambient stop of `--sp-shadow-1`. The selected state owns
    /// `layer.shadow*` for its money ring, so the sibling ambient layer must
    /// not linger underneath it.
    private func removeAmbientShadowLayer() {
        layer.sublayers?
            .first { $0.name == AppShadow.ambientShadow1LayerName }?
            .removeFromSuperlayer()
    }

    @objc
    private func handleTap() {
        onTap?()
    }
}

/// `UILabel` that pads its text content — used for the «Популярно» badge so it
/// hugs its (mixed-case) text plus a horizontal inset rather than relying on a
/// fixed width.
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
