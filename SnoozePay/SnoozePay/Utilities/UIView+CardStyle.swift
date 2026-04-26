import UIKit

/// Shared visual treatment for "card" containers across the app.
///
/// Light mode is the problem case: `secondarySystemBackground` (#FFFFFF) sits on
/// `systemGroupedBackground` (#F2F2F7) — only ~5% luminance delta. Without a
/// shadow + hairline border every screen reads as one undifferentiated block.
/// `AlarmCell` solved this for one cell type in IOS-063; this helper extracts
/// the styling so every card-shaped container (statistics widgets, balance
/// hero, top-up package row, transaction history row, etc.) renders with the
/// same affordance and we don't drift over time.
///
/// Callers must keep their card view's `clipsToBounds` / `masksToBounds` off
/// (the helper sets `masksToBounds = false`) — the shadow is rendered outside
/// the rounded bounds and is clipped by `clipsToBounds = true`.
extension UIView {

    /// Apply the standard card visual treatment: rounded corners, hairline
    /// border, subtle drop shadow.
    ///
    /// - Parameter cornerRadius: corner radius to use. Defaults to `AppRadius.md`
    ///   to match the existing `AlarmCell` look. Use `AppRadius.lg` for hero
    ///   cards (e.g. balance) where a slightly softer edge reads better.
    func applyCardStyle(cornerRadius: CGFloat = AppRadius.md) {
        layer.cornerRadius = cornerRadius
        // Subviews are constrained inside the card via Auto Layout, so they
        // won't overflow even without clipping the layer.
        layer.masksToBounds = false

        // Subtle drop shadow lifts the card off the background. In light mode
        // this is the primary visual separator since `secondarySystemBackground`
        // (#FFFFFF) sits on top of `systemGroupedBackground` (#F2F2F7) — only
        // ~5% luminance delta. In dark mode the shadow is barely visible (black
        // on near-black), and the border carries the work.
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.06
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 2)

        // Hairline border reinforces the edge in light mode (UIColor.separator
        // is fully opaque grey in light, faint in dark — auto-adapts).
        layer.borderWidth = 0.5
        layer.borderColor = AppColors.cardBorder.cgColor
    }

    /// Refresh the card's `borderColor` against the current trait collection.
    /// `CALayer.cgColor` doesn't auto-resolve dynamic `UIColor` values, so a
    /// light → dark switch would leave the border stuck at the previous mode's
    /// colour. Call from `layoutSubviews` and from a trait-change registration
    /// (or tableView cell `traitCollectionDidChange` equivalent).
    func refreshCardBorderColor() {
        layer.borderColor = AppColors.cardBorder.resolvedColor(
            with: traitCollection
        ).cgColor
    }

    /// Pre-rasterize the shadow against a rounded path so scrolling doesn't
    /// pay the per-pixel offscreen pass cost. Call from `layoutSubviews` once
    /// the view has its final bounds.
    func updateCardShadowPath(cornerRadius: CGFloat = AppRadius.md) {
        layer.shadowPath = UIBezierPath(
            roundedRect: bounds,
            cornerRadius: cornerRadius
        ).cgPath
    }
}

/// Self-maintaining card surface — applies the standard card style on init and
/// keeps `shadowPath` / `borderColor` in sync with `bounds` and trait changes
/// via `layoutSubviews`. Use anywhere a host VC would otherwise have to wire
/// up `viewDidLayoutSubviews` + `traitCollectionDidChange` boilerplate just to
/// keep a card looking right after rotation or a light/dark switch.
final class CardView: UIView {

    private let cornerRadius: CGFloat

    init(cornerRadius: CGFloat = AppRadius.md) {
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
        backgroundColor = AppColors.cardSurface
        translatesAutoresizingMaskIntoConstraints = false
        applyCardStyle(cornerRadius: cornerRadius)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 else { return }
        updateCardShadowPath(cornerRadius: cornerRadius)
        refreshCardBorderColor()
    }
}
