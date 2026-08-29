import UIKit

// MARK: - Snoozed-state subview builders + storage (#226)
//
// Split out of `AlarmFiringViewController+Snoozed.swift` so neither file trips
// SwiftLint's `file_length` cap. Builders are pure view factories; the
// associated-object slots mirror the +Theme storage pattern (the host type
// body is at the `type_body_length` limit so new stored properties can't live
// on the type itself). Main-thread only — the firing screen is main-only.

extension AlarmFiringViewController {

    // MARK: - zZ badge on the bell tile

    func installZzBadge() {
        guard snoozedZzBadge == nil else { return }
        let badge = PaddedLabel(insets: UIEdgeInsets(top: 2, left: 8, bottom: 2, right: 8))
        badge.text = "zZ"
        badge.font = AppFonts.mono(.bold, 10)
        badge.textColor = firingPalette?.accent ?? .white
        badge.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        badge.layer.cornerRadius = AppRadius.pill
        badge.layer.borderWidth = 1
        badge.layer.borderColor = (firingPalette?.pillBorder ?? UIColor.white.withAlphaComponent(0.22)).cgColor
        badge.layer.masksToBounds = true
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.isHidden = true
        view.addSubview(badge)
        snoozedZzBadge = badge

        // Top-right of the tile, offset −6/−8 per the JSX recipe.
        NSLayoutConstraint.activate([
            badge.trailingAnchor.constraint(equalTo: bellTile.trailingAnchor, constant: 6),
            badge.topAnchor.constraint(equalTo: bellTile.topAnchor, constant: -8)
        ])
    }

    // MARK: - Progressive pill

    /// «Прогрессив · N-й поспать ещё» pill — pad 6×12 r999, pain-tinted fill +
    /// border, leading 8pt glowing dot, caps `#FFB4A8` text.
    func makeProgressivePill() -> PaddedLabel {
        let pill = PaddedLabel(insets: UIEdgeInsets(top: 6, left: 30, bottom: 6, right: 12))
        pill.font = AppFonts.mono(.bold, 11)
        pill.textColor = UIColor(snoozedRGB: 0xFFB4A8)
        pill.backgroundColor = UIColor(snoozedRGB: 0xF4523F, alpha: 0.14)
        pill.layer.cornerRadius = AppRadius.pill
        pill.layer.borderWidth = 1
        pill.layer.borderColor = UIColor(snoozedRGB: 0xF4523F, alpha: 0.28).cgColor
        pill.layer.masksToBounds = true
        pill.translatesAutoresizingMaskIntoConstraints = false

        // Leading glowing dot (8pt) — drawn as a sibling inside the pill's
        // left padding so the pill keeps its single-label sizing.
        let dot = UIView()
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.backgroundColor = UIColor(snoozedRGB: 0xF4523F, alpha: 0.85)
        dot.layer.cornerRadius = 4
        dot.layer.shadowColor = UIColor(snoozedRGB: 0xF4523F).cgColor
        dot.layer.shadowRadius = 6
        dot.layer.shadowOpacity = 0.6
        dot.layer.shadowOffset = .zero
        pill.addSubview(dot)
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            dot.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 12),
            dot.centerYAnchor.constraint(equalTo: pill.centerYAnchor)
        ])
        pill.isAccessibilityElement = true
        pill.accessibilityIdentifier = "firing.snoozed.progressivePill"
        return pill
    }

    // MARK: - Charge ladder

    /// Build the empty 4-column ladder row (mt 16, gap 8). Columns are filled /
    /// recoloured by `rebuildLadder()` on every refresh.
    func makeLadderStack() -> UIStackView {
        let row = UIStackView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.axis = .horizontal
        row.alignment = .top
        row.spacing = AppSpacing.sp2   // 8pt
        row.accessibilityIdentifier = "firing.snoozed.ladder"
        return row
    }

    /// Rebuild the ladder columns from `viewModel.ladderSteps`. Each column is
    /// an amount label (mono 700 11) + a bar (h4 r2). done: #FFB4A8 label /
    /// #FF7A6B bar w28; current: theme-accent label + bar w10; future: muted
    /// white label + bar w10.
    func rebuildLadder() {
        guard let row = snoozedLadderStack else { return }
        row.arrangedSubviews.forEach {
            row.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        let accent = firingPalette?.accent ?? .white
        for step in viewModel.ladderSteps {
            row.addArrangedSubview(makeLadderColumn(step: step, accent: accent))
        }
    }

    private func makeLadderColumn(
        step: AlarmFiringViewModel.LadderStep,
        accent: UIColor
    ) -> UIStackView {
        let colours = ladderColours(for: step.state, accent: accent)

        let amount = UILabel()
        amount.text = "\(step.amount)"
        amount.font = AppFonts.mono(.bold, 11)
        amount.textColor = colours.label
        amount.textAlignment = .center

        let bar = UIView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.backgroundColor = colours.bar
        bar.layer.cornerRadius = 2

        let column = UIStackView(arrangedSubviews: [amount, bar])
        column.axis = .vertical
        column.alignment = .center
        column.spacing = AppSpacing.sp1   // 4pt
        NSLayoutConstraint.activate([
            bar.widthAnchor.constraint(equalToConstant: colours.barWidth),
            bar.heightAnchor.constraint(equalToConstant: 4)
        ])
        return column
    }

    private func ladderColours(
        for state: AlarmFiringViewModel.LadderStepState,
        accent: UIColor
    ) -> LadderColours {
        switch state {
        case .done:
            return LadderColours(label: UIColor(snoozedRGB: 0xFFB4A8), bar: UIColor(snoozedRGB: 0xFF7A6B), barWidth: 28)
        case .current:
            return LadderColours(label: accent, bar: accent, barWidth: 10)
        case .future:
            return LadderColours(
                label: UIColor.white.withAlphaComponent(0.32),
                bar: UIColor.white.withAlphaComponent(0.15),
                barWidth: 10
            )
        }
    }
}

// MARK: - Ladder column colours

/// Resolved colours + bar width for one ladder rung in the snoozed state.
private struct LadderColours {
    let label: UIColor
    let bar: UIColor
    let barWidth: CGFloat
}

// MARK: - Padded label

/// Capsule label with content insets — used for the `zZ` badge and the
/// progressive pill, which both need symmetric padding around a single line.
final class PaddedLabel: UILabel {
    private let insets: UIEdgeInsets

    init(insets: UIEdgeInsets) {
        self.insets = insets
        super.init(frame: .zero)
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

// MARK: - Associated-object storage

private var isSnoozedStateActiveKey: UInt8 = 0
private var countdownTimerKey: UInt8 = 0
private var snoozedCountdownLabelKey: UInt8 = 0
private var snoozedCenterStackKey: UInt8 = 0
private var snoozedProgressivePillKey: UInt8 = 0
private var snoozedLadderStackKey: UInt8 = 0
private var snoozedZzBadgeKey: UInt8 = 0

extension AlarmFiringViewController {

    var isSnoozedStateActive: Bool {
        get { (objc_getAssociatedObject(self, &isSnoozedStateActiveKey) as? Bool) ?? false }
        set { objc_setAssociatedObject(self, &isSnoozedStateActiveKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    var countdownTimer: Timer? {
        get { objc_getAssociatedObject(self, &countdownTimerKey) as? Timer }
        set { objc_setAssociatedObject(self, &countdownTimerKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    var snoozedCountdownLabel: UILabel? {
        get { objc_getAssociatedObject(self, &snoozedCountdownLabelKey) as? UILabel }
        set { objc_setAssociatedObject(self, &snoozedCountdownLabelKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    var snoozedCenterStack: UIStackView? {
        get { objc_getAssociatedObject(self, &snoozedCenterStackKey) as? UIStackView }
        set { objc_setAssociatedObject(self, &snoozedCenterStackKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    var snoozedProgressivePill: PaddedLabel? {
        get { objc_getAssociatedObject(self, &snoozedProgressivePillKey) as? PaddedLabel }
        set { objc_setAssociatedObject(self, &snoozedProgressivePillKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    var snoozedLadderStack: UIStackView? {
        get { objc_getAssociatedObject(self, &snoozedLadderStackKey) as? UIStackView }
        set { objc_setAssociatedObject(self, &snoozedLadderStackKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    var snoozedZzBadge: PaddedLabel? {
        get { objc_getAssociatedObject(self, &snoozedZzBadgeKey) as? PaddedLabel }
        set { objc_setAssociatedObject(self, &snoozedZzBadgeKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}

// MARK: - Hex helper (file-scoped)

private extension UIColor {
    /// `0xRRGGBB` literal initializer for the snoozed-state colours. File-scoped
    /// copy mirroring the sibling +Snoozed file (Swift `private` is file-scope).
    convenience init(snoozedRGB rgb: UInt32, alpha: CGFloat = 1) {
        let red = CGFloat((rgb >> 16) & 0xFF) / 255.0
        let green = CGFloat((rgb >> 8) & 0xFF) / 255.0
        let blue = CGFloat(rgb & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}
