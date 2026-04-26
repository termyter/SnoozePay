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
        // Drop shadow lifts the card off the background. Light values keep it
        // subtle so we don't read as elevated above accent banners.
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.06
        layer.shadowRadius = 4
        layer.shadowOffset = CGSize(width: 0, height: 1)
        // Hairline border reinforces the edge in light mode (UIColor.separator
        // is fully opaque grey in light, very faint in dark — auto-adapts).
        layer.borderWidth = 0.5
        layer.borderColor = UIColor.separator.cgColor
    }

    /// Refresh the cached `cgColor` border with the current trait collection so
    /// dynamic colours re-resolve after a light/dark switch. Call from
    /// `traitCollectionDidChange` or via `registerForTraitChanges` on iOS 17+.
    func refreshCardBorderForTraitChange() {
        layer.borderColor = UIColor.separator.resolvedColor(with: traitCollection).cgColor
    }

    /// Pre-rasterise the shadow against the rounded card frame so scrolling
    /// doesn't pay the per-pixel offscreen pass cost. Call from
    /// `layoutSubviews()`.
    func updateCardShadowPath(cornerRadius: CGFloat = AppRadius.md) {
        layer.shadowPath = UIBezierPath(
            roundedRect: bounds,
            cornerRadius: cornerRadius
        ).cgPath
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
        if position != .middle {
            surface.layer.shadowColor = UIColor.black.cgColor
            surface.layer.shadowOpacity = 0.05
            surface.layer.shadowRadius = 4
            surface.layer.shadowOffset = CGSize(width: 0, height: 1)
        }

        backgroundView = surface
    }
}
