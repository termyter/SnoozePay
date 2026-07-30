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
            stack.addArrangedSubview(Self.makePip(number: index + 1, lit: index < lit))
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

    private static func makePip(number: Int, lit: Bool) -> UIView {
        let pip = UIView()
        pip.translatesAutoresizingMaskIntoConstraints = false
        pip.layer.cornerRadius = AppRadius.sm
        pip.layer.cornerCurve = .continuous
        pip.layer.masksToBounds = true
        pip.heightAnchor.constraint(equalToConstant: pipSide).isActive = true
        pip.widthAnchor.constraint(equalToConstant: pipSide).isActive = true

        if lit {
            let gradient = CAGradientLayer()
            gradient.colors = SPSupport.moneyGradientColors
            gradient.locations = SPSupport.moneyGradientLocations
            gradient.startPoint = SPSupport.gradientStart
            gradient.endPoint = SPSupport.gradientEnd
            gradient.cornerRadius = AppRadius.sm
            // Fixed 32×32 anchors mean the frame never changes after the first
            // layout pass, so a one-shot assignment on the next runloop turn is
            // enough — no `layoutSubviews` bookkeeping needed.
            gradient.frame = CGRect(x: 0, y: 0, width: pipSide, height: pipSide)
            pip.layer.insertSublayer(gradient, at: 0)
        } else {
            pip.backgroundColor = AppColors.whiteOverlay08
        }

        let label = UILabel()
        label.text = "\(number)"
        label.font = AppFonts.mono(.bold, 13)
        label.textColor = lit ? AppColors.fgOnMoney : AppColors.fg3
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        pip.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: pip.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: pip.centerYAnchor)
        ])
        return pip
    }
}
