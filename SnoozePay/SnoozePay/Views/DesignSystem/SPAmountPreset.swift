import UIKit

/// Top-up amount preset tile — `.sp-preset` in `components.css`.
///
/// Visual: outlined card (1.5pt `stroke1`) with a centered mono amount
/// (`moneyMd` 20pt) and an optional secondary label (`meta` 13pt). When
/// `selected` is true the border switches to `money500`, the fill takes a
/// 10% money tint, and a 4pt outer glow ring renders. A "Популярно" badge
/// floats above the top edge when `popular` is true.
final class SPAmountPreset: UIControl {

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
    private let popularBadge = UILabel()
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
        valueLabel.text = value.formattedRubles()
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
        valueLabel.font = AppTypography.moneyMd
        valueLabel.textColor = AppColors.fg1
        valueLabel.textAlignment = .center

        labelView.translatesAutoresizingMaskIntoConstraints = false
        labelView.font = AppTypography.meta
        labelView.textColor = AppColors.fg3
        labelView.textAlignment = .center

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 4
        stack.isUserInteractionEnabled = false
        stack.addArrangedSubview(valueLabel)
        stack.addArrangedSubview(labelView)
        addSubview(stack)

        // Popular badge — small caps pill that floats above the top edge.
        popularBadge.translatesAutoresizingMaskIntoConstraints = false
        popularBadge.attributedText = NSAttributedString(
            string: "ПОПУЛЯРНО",
            attributes: [
                .font: AppTypography.caps,
                .kern: 12 * 0.12,
                .foregroundColor: AppColors.fgOnMoney
            ]
        )
        popularBadge.backgroundColor = AppColors.money500
        popularBadge.layer.cornerRadius = 10
        popularBadge.layer.masksToBounds = true
        popularBadge.textAlignment = .center
        addSubview(popularBadge)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 88),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            popularBadge.centerXAnchor.constraint(equalTo: centerXAnchor),
            popularBadge.centerYAnchor.constraint(equalTo: topAnchor),
            popularBadge.heightAnchor.constraint(equalToConstant: 20),
            popularBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 86)
        ])
    }

    private func applySelectionState(animated: Bool) {
        let apply: () -> Void = {
            if self.isSelected {
                self.backgroundColor = AppColors.money500.withAlphaComponent(0.10)
                self.layer.borderColor = AppColors.money500.cgColor
                // Tight selection ring: 4pt radius / 0.10 opacity reads as a
                // crisp brand outline rather than a diffuse glow that bled
                // into adjacent presets at radius 8 / opacity 0.18.
                self.layer.shadowColor = AppColors.money500.cgColor
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
