import UIKit

/// Compact badge / chip primitive — `.sp-pill` in `components.css`.
///
/// Visual: 26pt tall capsule with 12pt horizontal padding, 6pt gap between
/// optional leading icon and the label. Tones set both the background fill and
/// the foreground text — a low-alpha brand tint for `.neutral` / `.money` /
/// `.pain`, and since #580 a SOLID amber for `.warn` (see `palette(for:)`).
/// Use for status flags («Активный», «Популярно», «Списано»), not for tap
/// targets — tap targets belong on `SPButton(size: .sm)` so they hit the 44pt
/// minimum.
final class SPPill: UIView {

    enum Tone {
        case neutral   // White overlay + fg2 text
        case money     // Money-tint overlay + money300 text
        case pain      // Pain-tint overlay + pain300 text
        case warn      // SOLID warn fill + fgOnWarn ink (#580)
    }

    // MARK: - Subviews

    private let stack = UIStackView()
    private let iconView = UIImageView()
    private let label = UILabel()

    let tone: Tone

    // MARK: - Init

    /// - Parameters:
    ///   - text: Caps-styled label. The `.sp-pill` recipe applies only the
    ///     `--sp-t-caps` font + default `.12em` tracking — no `text-transform`,
    ///     so the caller's casing is preserved (the design mixes case, e.g.
    ///     «Популярно»).
    ///   - tone: Background + text colour mapping. Defaults to `.neutral`.
    ///   - icon: Optional 12pt leading icon (rendered as template, tinted
    ///     to match the label) — JSX chips use `<Icon size={12} />`.
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
        // Owns its autoresizing flag. This view activates a required
        // `heightAnchor` on ITSELF (below), which cannot coexist with the
        // constraints UIKit synthesises from the `.zero` frame it is born
        // with. A caller who forgets the reset gets no error: the engine pays
        // for the collision out of whatever else is breakable, which in #467
        // was the intrinsic height of the SIBLINGS — they kept their
        // x/y/width and measured 0 tall, and the screen read as blank. Owning
        // it here makes forgetting impossible; call sites that still set it
        // are harmlessly redundant (#584).
        translatesAutoresizingMaskIntoConstraints = false

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
            iconView.widthAnchor.constraint(equalToConstant: 12),
            iconView.heightAnchor.constraint(equalToConstant: 12)
        ])

        applyTone()
    }

    /// Update the pill's caps label in place. Used by callers that re-title
    /// a long-lived pill instance (e.g. the progressive-snooze indicator on
    /// the firing screen counts up «1-е откладывание» → «2-е откладывание» → ...).
    func setText(_ text: String) {
        // `.sp-pill` uses the bold 12pt caps font with the default caps
        // tracking (`.12em` per `tokens.css` `--sp-t-caps` / `.sp-caps`) and
        // *no* `text-transform`, so the caller's mixed-case string is kept
        // verbatim.
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning
            ]
        )
        label.attributedText = attributed
    }

    /// Two-tier balance variant — a muted caps label segment («Баланс») next
    /// to a bold value segment («840 ₽»), per `SPDawnV3.jsx:97-109`
    /// (`dawn-bal__label` at .55 alpha + bold `dawn-bal__value`). Both segments
    /// inherit the tone foreground; only the label is dimmed. The value keeps a
    /// hair of tracking so the mono-ish digits don't crowd the glyph.
    func setBalance(label labelText: String, value: String) {
        let ink = label.textColor ?? AppColors.fg2
        let result = NSMutableAttributedString(
            string: labelText,
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: ink.withAlphaComponent(0.55)
            ]
        )
        result.append(NSAttributedString(
            string: "  \(value)",
            attributes: [
                .font: AppFonts.sans(.bold, 13),
                .kern: 0.2,
                .foregroundColor: ink
            ]
        ))
        label.attributedText = result
    }

    private func setIcon(_ icon: UIImage?) {
        if let icon = icon {
            iconView.image = icon.withRenderingMode(.alwaysTemplate)
            iconView.isHidden = false
        } else {
            iconView.isHidden = true
        }
    }

    /// Fill + ink per tone. Internal (not private) so
    /// `SPPillWarnChipContrastTests` measures the SAME pair the view paints
    /// instead of a copy of it.
    ///
    /// `.warn` is the one tone that is NOT a tint (#580). The canon recipe
    /// (`.sp-pill--warn` in `tokens.css`: `rgba(245,158,11,.18)` + `warn-300`)
    /// was implemented byte-for-byte and still failed in both themes, because
    /// an 18% amber composites into whatever is behind it:
    ///
    ///     dark  — fill #3E3328 over the `bgRaised` card. Ink reads 8.71:1,
    ///             but the CHIP reads 1.38:1 against its card (1.63:1 against
    ///             the page): a brown smear, not a chip. That brown is why the
    ///             list still looked like the pre-#520 bronze.
    ///     light — fill #FDEED3 over the white card, inked `warn300` `#BE7B09`
    ///             at 3.04:1 — under the 4.5:1 floor for its 12pt caps.
    ///
    /// Raising the alpha cannot fix it: the chip stays brown until ~45% and by
    /// the time the fill is really amber the light ink on it is gone (1.53:1 at
    /// 100%). So `.warn` takes the fill half of the warn role at full strength
    /// and the ink solved for it — the same pair #520 built for light:
    ///
    ///     both themes — `fgOnWarn` on solid `warnFill500` = 8.79:1
    ///     dark  — chip vs card 7.89:1, vs page 9.26:1
    ///     light — chip vs card 2.15:1 (amber's ceiling on white; it was
    ///             1.15:1 as a wash — the dark ink is what marks the chip out)
    ///
    /// `warnFill500` and `fgOnWarn` are both theme-flat, so the two themes now
    /// render this chip identically — which is the point. A deliberate
    /// departure from `tokens.css` for this tone only, like #489 was.
    ///
    /// The other three tones stay tints: `.money` / `.pain` carry no such
    /// defect and their ramps were not part of the #580 decision.
    static func palette(for tone: Tone) -> (fill: UIColor, ink: UIColor) {
        switch tone {
        case .neutral:
            return (AppColors.whiteOverlay08, AppColors.fg2)
        case .money:
            // `rgba(46,219,159,.16)` — money400 at 16% over surface.
            return (AppColors.money400.withAlphaComponent(0.16), AppColors.money300)
        case .pain:
            return (AppColors.pain500.withAlphaComponent(0.16), AppColors.pain300)
        case .warn:
            return (AppColors.warnFill500, AppColors.fgOnWarn)
        }
    }

    private func applyTone() {
        let palette = Self.palette(for: tone)
        backgroundColor = palette.fill
        label.textColor = palette.ink
        iconView.tintColor = palette.ink
    }
}
