import UIKit

/// Row of numbered "day pips" used by the streak celebration sheet
/// (`StreakModalV2` in `SPScreensV2.jsx`, artboard `28-streak`).
///
/// Each pip is a 32×32 rounded square (`AppRadius.sm`) carrying its 1-based
/// day number in the mono face. Completed days are filled with the money
/// gradient and `fgOnMoney` digits; the remaining days fall back to the faint
/// `whiteOverlay08` chip with `fg3` digits.
///
/// Extracted out of `StreakModalViewController` (#347) so the modal stays
/// under the SwiftLint type-body cap once the money hero and the two-button
/// footer land; the strip has no dependency on the modal and is reusable by
/// any future streak surface.
final class SPStreakPipStrip: UIView {

    /// Pip edge length in points — matches the 32px square in the design.
    private static let pipSide: CGFloat = 32

    /// Gap between pips. Design uses 6pt, which sits between `sp1` and `sp2`
    /// on the 4pt grid, so it stays a named constant here rather than a bare
    /// literal at the call site (#289).
    private static let pipGap: CGFloat = 6

    private let stack = UIStackView()

    /// - Parameters:
    ///   - completed: number of lit pips. Clamped into `0...total`.
    ///   - total: how many pips the strip renders. Defaults to the 7-day week
    ///     shown in the design.
    init(completed: Int, total: Int = 7) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = Self.pipGap
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        let lit = max(0, min(total, completed))
        for index in 0..<max(0, total) {
            stack.addArrangedSubview(
                StreakPipView(number: index + 1, lit: index < lit, side: Self.pipSide)
            )
        }

        // The strip centres inside its container; the container itself is free
        // to stretch to the sheet's full width.
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Pip

/// One 32×32 day pip.
///
/// A class rather than a `static` factory returning a configured `UIView` so
/// the lit variant has somewhere to hang a trait observer:
/// `CAGradientLayer.colors` stores plain `CGColor`s that never follow the
/// dynamic token they came from, so a strip built in one theme kept that
/// theme's money ramp under `fgOnMoney` digits that did re-resolve (#507).
private final class StreakPipView: UIView {

    /// Nil for unlit pips — they are a flat `whiteOverlay08` chip.
    private let gradient: CAGradientLayer?

    init(number: Int, lit: Bool, side: CGFloat) {
        self.gradient = lit ? CAGradientLayer() : nil
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = AppRadius.sm
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
        heightAnchor.constraint(equalToConstant: side).isActive = true
        widthAnchor.constraint(equalToConstant: side).isActive = true

        if let gradient = gradient {
            gradient.locations = SPSupport.moneyGradientLocations
            gradient.startPoint = SPSupport.gradientStart
            gradient.endPoint = SPSupport.gradientEnd
            gradient.cornerRadius = AppRadius.sm
            // Fixed 32×32 anchors mean the frame never changes after the first
            // layout pass, so a one-shot assignment is enough — no
            // `layoutSubviews` bookkeeping needed.
            gradient.frame = CGRect(x: 0, y: 0, width: side, height: side)
            layer.insertSublayer(gradient, at: 0)
            refreshGradientColors()
            if #available(iOS 17.0, *) {
                registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: StreakPipView, _) in
                    view.refreshGradientColors()
                }
            }
        } else {
            backgroundColor = AppColors.whiteOverlay08
        }

        let label = UILabel()
        label.text = "\(number)"
        label.font = AppFonts.mono(.bold, 13)
        label.textColor = lit ? AppColors.fgOnMoney : AppColors.fg3
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @available(iOS, deprecated: 17.0, message: "Replaced by registerForTraitChanges; kept for iOS 15/16.")
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if #available(iOS 17.0, *) { return }
        refreshGradientColors()
    }

    /// Re-resolve the money ramp against THIS pip's traits.
    private func refreshGradientColors() {
        gradient?.colors = SPSupport.moneyGradientColors(for: traitCollection)
    }
}
