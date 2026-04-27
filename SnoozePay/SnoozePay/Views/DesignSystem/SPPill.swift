import UIKit

/// Compact badge / chip primitive — `.sp-pill` in `components.css`.
///
/// Visual: 26pt tall capsule with 12pt horizontal padding, 6pt gap between
/// optional leading icon and the label. Tones tint both the background fill
/// (low-alpha brand colour) and the foreground text. Use for status flags
/// ("Активный", "Популярно", "Списано"), not for tap targets — tap targets
/// belong on `SPButton(size: .sm)` so they hit the 44pt minimum.
final class SPPill: UIView {

    enum Tone {
        case neutral   // White overlay + fg2 text
        case money     // Money-tint overlay + money300 text
        case pain      // Pain-tint overlay + pain300 text
        case warn      // Warn-tint overlay + warn300 text
    }

    // MARK: - Subviews

    private let stack = UIStackView()
    private let iconView = UIImageView()
    private let label = UILabel()

    let tone: Tone

    // MARK: - Init

    /// - Parameters:
    ///   - text: Caps-styled label (uppercased automatically per the
    ///     `--sp-t-caps` recipe — bold 12pt + 0.14em tracking).
    ///   - tone: Background + text colour mapping. Defaults to `.neutral`.
    ///   - icon: Optional 14pt leading icon (rendered as template, tinted
    ///     to match the label).
    init(text: String, tone: Tone = .neutral, icon: UIImage? = nil) {
        self.tone = tone
        super.init(frame: .zero)
        configure()
        setText(text)
        setIcon(icon)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        // Pill — fully rounded.
        layer.cornerRadius = bounds.height / 2
    }

    // MARK: - Configuration

    private func configure() {
        layer.cornerRadius = 13
        layer.masksToBounds = true

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit

        label.translatesAutoresizingMaskIntoConstraints = false
        // `--sp-t-caps: 700 12px/16px Manrope` with letter-spacing .14em.
        label.font = AppTypography.caps
        label.adjustsFontForContentSizeCategory = false

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = AppSpacing.sp1 + 2   // 6pt — matches `gap: 6px`
        stack.alignment = .center
        stack.isUserInteractionEnabled = false
        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(label)
        addSubview(stack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 26),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14)
        ])

        applyTone()
    }

    private func setText(_ text: String) {
        // CSS pairs caps tracking (.14em ≈ 12 * 0.14 = 1.68pt) with the
        // bold 12pt size; bake that into an attributed string so the label
        // stays in one node (not a stack of label + spacer).
        let attributed = NSAttributedString(
            string: text.uppercased(),
            attributes: [
                .font: AppTypography.caps,
                .kern: 12 * 0.14
            ]
        )
        label.attributedText = attributed
    }

    private func setIcon(_ icon: UIImage?) {
        if let icon = icon {
            iconView.image = icon.withRenderingMode(.alwaysTemplate)
            iconView.isHidden = false
        } else {
            iconView.isHidden = true
        }
    }

    private func applyTone() {
        // swiftlint:disable identifier_name
        let bg: UIColor
        let fg: UIColor
        // swiftlint:enable identifier_name
        switch tone {
        case .neutral:
            bg = AppColors.whiteOverlay08
            fg = AppColors.fg2
        case .money:
            // `rgba(46,219,159,.16)` — money400 at 16% over surface.
            bg = AppColors.money400.withAlphaComponent(0.16)
            fg = AppColors.money300
        case .pain:
            bg = AppColors.pain500.withAlphaComponent(0.16)
            fg = AppColors.pain300
        case .warn:
            bg = AppColors.warn500.withAlphaComponent(0.18)
            fg = AppColors.warn300
        }
        backgroundColor = bg
        label.textColor = fg
        iconView.tintColor = fg
    }
}
