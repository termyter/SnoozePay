import UIKit

/// Card-styling helpers used to give containers visible hierarchy in light mode.
///
/// Light mode pairs `systemGroupedBackground` (#F2F2F7) with
/// `secondarySystemBackground` (#FFFFFF) — only ~5% luminance delta. Without a
/// shadow + hairline border the cards visually merge into the page and the UI
/// reads as one beige slab. AlarmCell solved this for one cell type; this
/// extension generalises the same recipe so every card on Settings, Statistics,
/// CreateAlarm and TopUp shares the styling.
extension UIView {

    /// Apply the standard card surface: rounded corners, hairline border, soft
    /// drop shadow. Caller is responsible for keeping `masksToBounds = false`
    /// (the shadow needs to render outside `bounds`); subviews should be
    /// constrained inside the card via Auto Layout instead of being clipped.
    ///
    /// Use `cornerRadius` to override the default `AppRadius.md` (e.g. 8pt for
    /// individual table-view cells nested inside `.insetGrouped` sections that
    /// already provide outer rounding).
    func applyCardStyle(cornerRadius: CGFloat = AppRadius.md) {
        backgroundColor = AppColors.surface
        layer.cornerRadius = cornerRadius
        layer.masksToBounds = false
        // Brand `shadow1` is theme-aware: dark mode gets a single deep stop
        // (`rgba(0,0,0,.35)`); light mode gets a two-stop recipe — the wider
        // `0 4px 14px` stop renders here on `view.layer`, and the narrower
        // `0 1px 3px` ambient stop is added as a sibling sublayer by
        // `updateCardShadowPath` so cards lift cleanly off the near-white
        // surface instead of reading as a flat slab.
        AppShadow.shadow1(for: traitCollection).apply(to: layer)
        AppShadow.installAmbientShadow1Layer(
            on: layer,
            cornerRadius: cornerRadius,
            trait: traitCollection
        )
        // Hairline border reinforces the edge — `stroke1` is theme-aware
        // (8% white on dark, 8% near-black ink on light), so the border has
        // visible weight in light mode where the system's grey separator
        // washes out against the brand ink.
        // Hairline width — `traitCollection.displayScale` resolves to the
        // current screen's scale (1×, 2× or 3×). Falls back to 1× if the
        // view isn't yet in a window (`displayScale == 0`).
        let scale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 1
        layer.borderWidth = 1.0 / scale
        layer.borderColor = AppColors.stroke1.resolvedColor(with: traitCollection).cgColor
    }

    /// Refresh the cached `cgColor` border + shadow with the current trait
    /// collection so dynamic colours re-resolve after a light/dark switch.
    /// Call from `traitCollectionDidChange` or via `registerForTraitChanges`
    /// on iOS 17+.
    func refreshCardBorderForTraitChange() {
        layer.borderColor = AppColors.stroke1.resolvedColor(with: traitCollection).cgColor
        // Re-resolve the shadow recipe — dark and light use different
        // colours, opacities, offsets and radii (single-stop deep shadow vs
        // wider soft shadow), so it isn't enough to just refresh `cgColor`.
        AppShadow.shadow1(for: traitCollection).apply(to: layer)
        // Light mode adds a second narrow ambient stop via a sibling
        // sublayer; dark mode removes it. Pass through the host's current
        // corner radius so the ambient shadow path matches the visible
        // rounded shape.
        AppShadow.installAmbientShadow1Layer(
            on: layer,
            cornerRadius: layer.cornerRadius,
            trait: traitCollection
        )
    }

    /// Pre-rasterise the shadow against the rounded card frame so scrolling
    /// doesn't pay the per-pixel offscreen pass cost. Call from
    /// `layoutSubviews()`.
    func updateCardShadowPath(cornerRadius: CGFloat = AppRadius.md) {
        layer.shadowPath = UIBezierPath(
            roundedRect: bounds,
            cornerRadius: cornerRadius
        ).cgPath
        // The two-stop `shadow1` recipe in light mode owns a sibling
        // ambient layer that needs its frame + path resized whenever the
        // host's bounds change. `installAmbientShadow1Layer` is idempotent
        // and short-circuits on dark mode, so we can safely fan it out
        // from every layoutSubviews-driven update path.
        AppShadow.installAmbientShadow1Layer(
            on: layer,
            cornerRadius: cornerRadius,
            trait: traitCollection
        )
    }
}

/// Drop-in card surface that rasterises its shadow path on layout and refreshes
/// its border `cgColor` when the trait collection switches between light and
/// dark. Use this anywhere a static `UIView` previously held card decoration
/// — it removes the obligation on the call site to remember to update the
/// shadow path / border colour.
final class CardView: UIView {

    private let cardCornerRadius: CGFloat

    init(cornerRadius: CGFloat = AppRadius.md) {
        self.cardCornerRadius = cornerRadius
        super.init(frame: .zero)
        applyCardStyle(cornerRadius: cornerRadius)
        // CALayer's `cgColor` properties don't auto-resolve dynamic UIColors,
        // so refresh the border whenever the trait collection (light/dark) flips.
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: CardView, _) in
            view.refreshCardBorderForTraitChange()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateCardShadowPath(cornerRadius: cardCornerRadius)
    }
}

/// Position of a row inside a section — drives which corners get rounded
/// when an `.insetGrouped` cell is given an explicit card-style background.
/// Resolves so callers don't have to track first/last/middle/single indices
/// manually.
enum CardRowPosition {
    case single
    case first
    case middle
    case last

    /// Map (rowIndex, totalRowsInSection) to a `CardRowPosition`.
    static func resolve(row: Int, totalRows: Int) -> CardRowPosition {
        if totalRows <= 1 { return .single }
        if row == 0 { return .first }
        if row == totalRows - 1 { return .last }
        return .middle
    }

    /// CALayer corner mask matching this position. `.middle` rows stay
    /// rectangular so they tile flush against neighbours.
    var maskedCorners: CACornerMask {
        switch self {
        case .single:
            return [
                .layerMinXMinYCorner, .layerMaxXMinYCorner,
                .layerMinXMaxYCorner, .layerMaxXMaxYCorner
            ]
        case .first: return [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        case .last: return [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        case .middle: return []
        }
    }
}

extension UITableViewCell {

    /// Style an `.insetGrouped` cell as part of a card-styled section: surface
    /// fill, rounded outer corners, and a subtle drop shadow on the rows that
    /// touch the section's outer edges. Middle rows skip the shadow so
    /// adjacent rows don't double-stack their drop shadows.
    ///
    /// We deliberately omit a per-cell border because each cell drawing its
    /// own border would render double-thick separators between adjacent rows
    /// in the same section — the existing system row separator already gives
    /// us the inner divider, and the drop shadow + surface contrast carry the
    /// outer edge in light mode.
    ///
    /// In light mode this gives `.insetGrouped` sections the same lift as the
    /// alarm card on the home screen, without fighting the system's free
    /// row separators.
    func styleAsCardRow(position: CardRowPosition, cornerRadius: CGFloat = AppRadius.md) {
        // The system's default `backgroundColor` already paints
        // `secondarySystemBackground`. Wrap that in a custom `backgroundView`
        // so we can draw the rounded corners + shadow ourselves.
        backgroundColor = .clear

        let surface = UIView()
        surface.backgroundColor = AppColors.surface
        surface.layer.cornerRadius = cornerRadius
        surface.layer.maskedCorners = position.maskedCorners
        surface.layer.masksToBounds = false

        // Drop shadow only on the rows that paint the section's outer top or
        // bottom — middle rows would otherwise overlap into neighbours.
        // Re-uses the theme-aware brand `shadow1` so the row lift matches
        // free-standing CardViews on the same screen.
        if position != .middle {
            AppShadow.shadow1(for: traitCollection).apply(to: surface.layer)
        }

        backgroundView = surface
    }
}
