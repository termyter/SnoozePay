import UIKit

/// A `UILabel` whose glyphs are painted with a gradient instead of a flat
/// colour — the design system's "money hero" treatment (`--sp-grad-money` +
/// `background-clip: text`).
///
/// ## Why this is a view and not a call site
///
/// The mask has to be (re)rasterised **after** the label's bounds are resolved.
/// Hosts used to drive it from their own `viewDidLayoutSubviews`, which is a
/// trap: a view controller's layout callback fires once its *immediate*
/// subviews are placed, but a label nested two levels down (sheet → stack →
/// label) still has a zero rect at that moment. The guard inside
/// `applyGradientMask` then bailed out and never ran again — the label kept its
/// flat fallback colour and the gradient silently never appeared (#347 review;
/// the same defect is live in `SPBalanceCard`, tracked separately).
///
/// Owning the timing here removes the whole class of bug: `layoutSubviews` is
/// called on *this* label exactly when its own bounds are final, and again on
/// every resize / text change, so the mask can never go stale or be skipped.
final class SPGradientTextLabel: UILabel {

    private let gradient = CAGradientLayer()

    /// Guards against re-rasterising the mask on every layout pass — the image
    /// only depends on the resolved size and the string.
    private var appliedKey: String?

    /// - Parameters:
    ///   - colors: gradient stops, e.g. `SPSupport.moneyGradientColors`.
    ///   - locations: stop positions matching `colors`.
    ///   - startPoint / endPoint: unit-space gradient direction.
    init(
        colors: [CGColor],
        locations: [NSNumber],
        startPoint: CGPoint,
        endPoint: CGPoint
    ) {
        super.init(frame: .zero)
        gradient.colors = colors
        gradient.locations = locations
        gradient.startPoint = startPoint
        gradient.endPoint = endPoint
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var text: String? {
        didSet {
            guard text != oldValue else { return }
            appliedKey = nil
            setNeedsLayout()
        }
    }

    override var font: UIFont! {
        didSet {
            appliedKey = nil
            setNeedsLayout()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let key = "\(bounds.size)|\(text ?? "")"
        guard appliedKey != key else { return }
        applyGradientMask(gradient)
        // Only remember the key once the mask actually landed — the helper
        // no-ops on a zero rect, and that pass must not be cached as done.
        if gradient.mask != nil {
            appliedKey = key
        }
    }
}
