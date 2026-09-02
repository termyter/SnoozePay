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
        // `.sp-card` fills the brand surface token (`--sp-bg-1`), not the
        // system `secondarySystemBackground` the legacy recipe used — so
        // legacy cards line up tonally with `SPCard(.surface)`.
        backgroundColor = AppColors.bg1
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
        layer.borderWidth = hairlineWidth
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

    /// Edges this row shares with a neighbour — not really the card's edge at
    /// all, just the seam where the section continues.
    ///
    /// The AMBIENT stop's mask must not reach across these: the surface on the
    /// far side is the next row's `bg1`, and the stop's interior painted there
    /// reads as a boundary the section does not have (#674). Only the ambient
    /// stop — the key stop is not masked and still casts into the seam, at a
    /// measured 6/255 in light and 4/255 in dark.
    /// `CardRowBandingTests.testTheSeamBetweenTwoRows_…` holds this, and it
    /// asserts a GAP against a control rendered in the same run rather than a
    /// threshold on one number — so do not go looking there for a constant.
    ///
    /// `.middle` answers `[.top, .bottom]` for a caller that never arrives:
    /// a middle row installs no stop at all. The mapping is kept correct
    /// rather than removed — see `CardRowSeamShadowTests.testAMiddleRow_…`.
    var openEdges: UIRectEdge {
        switch self {
        case .single: return []
        case .first: return .bottom
        case .last: return .top
        case .middle: return [.top, .bottom]
        }
    }
}

extension UITableViewCell {

    /// Style an `.insetGrouped` cell as part of a card-styled section: brand
    /// surface fill, rounded outer corners, drop shadow on the rows that touch
    /// the section's outer edges, and a hairline outline around the section.
    ///
    /// In light mode this gives `.insetGrouped` sections the same lift as the
    /// alarm card on the home screen: `bg1` is `#FFFFFF` against a `#F4F6FB`
    /// page, so the shadow alone leaves the card barely detached — the border
    /// is what actually draws the edge (#496).
    func styleAsCardRow(position: CardRowPosition, cornerRadius: CGFloat = AppRadius.sm) {
        // The system's default `backgroundColor` already paints
        // `secondarySystemBackground`. Wrap that in a custom `backgroundView`
        // so we can draw the rounded corners + shadow + outline ourselves.
        backgroundColor = .clear
        backgroundView = CardRowBackgroundView(position: position, cornerRadius: cornerRadius)
    }
}

/// Background view behind a card-styled `.insetGrouped` row.
///
/// Owns the three pieces of decoration a row contributes to its section's
/// card: the `bg1` fill, the brand `shadow1` on the rows that touch the outer
/// top/bottom, and an *edge-aware* hairline outline.
///
/// The outline is a path rather than `layer.borderWidth` because a full
/// four-sided border per row renders double-thick where two rows meet, and
/// competes with the system's free row separator. Each row instead strokes
/// only the edges it contributes to the section boundary: side rails always,
/// plus the rounded top on `.first` and the rounded bottom on `.last`.
final class CardRowBackgroundView: UIView {

    private let position: CardRowPosition
    private let cardCornerRadius: CGFloat
    private let outline = CAShapeLayer()

    init(position: CardRowPosition, cornerRadius: CGFloat) {
        self.position = position
        self.cardCornerRadius = cornerRadius
        super.init(frame: .zero)
        // `bg1` rather than `secondarySystemBackground`: identical `#FFFFFF`
        // in light, but the brand `#0E1320` in dark instead of the system's
        // warm `#1C1C1E`, so rows match `SPCard`/`CardView` on the same screen.
        backgroundColor = AppColors.bg1
        layer.cornerRadius = cornerRadius
        layer.maskedCorners = position.maskedCorners
        layer.masksToBounds = false
        outline.fillColor = UIColor.clear.cgColor
        layer.addSublayer(outline)
        applyThemedDecoration()
        // `cgColor` doesn't track dynamic UIColors, and the shadow recipe
        // differs per theme — re-resolve both when the style flips.
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: CardRowBackgroundView, _) in
            view.applyThemedDecoration()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        outline.frame = bounds
        outline.path = outlinePath(lineWidth: outline.lineWidth)
        guard position != .middle else { return }
        // The ambient stop is the half of this that shows: masking it out of
        // the seam takes the light-mode band from 11/255 to 6/255, measured on
        // two stacked rows (`CardRowBandingTests.testTheSeamBetweenTwoRows_…`,
        // where 11 is that test's own control — an earlier note here said 10,
        // which came from a different control: a full revert of the PR).
        //
        // The key stop's path is corrected for honesty, not for pixels. The
        // layer's real silhouette is part-square via `maskedCorners`, and a
        // fully rounded `shadowPath` described a shape the layer does not have.
        // Reverting just this line moves the rendered seam by NOTHING — 6/255
        // light and 4/255 dark either way — because the corners it fixes sit
        // where the two rows' own fills already cover the difference. Claiming
        // it fixes the seam, or that it changes dark mode, would be wrong; it
        // is held at the path level by `CardRowSeamShadowTests`.
        //
        // Pushing the key path past the seam the way the ambient mask is pushed
        // would make things worse, not better: a shadow is always cast around
        // whatever path it is given, so growing it moves the band deeper into
        // the neighbour instead of removing it.
        layer.shadowPath = AppShadow.cardPath(
            bounds,
            cornerRadius: cardCornerRadius,
            corners: position.maskedCorners
        )
        AppShadow.installAmbientShadow1Layer(
            on: layer,
            cornerRadius: cardCornerRadius,
            trait: traitCollection,
            corners: [], // MUTATION #692 run C — drops the rounded half of `corners`
            openEdges: position.openEdges
        )
    }

    /// Re-resolve everything that caches a `cgColor` or branches on theme.
    private func applyThemedDecoration() {
        // Drop shadow only on the rows painting the section's outer top or
        // bottom — middle rows would otherwise overlap into neighbours.
        if position != .middle {
            AppShadow.shadow1(for: traitCollection).apply(to: layer)
        }
        outline.lineWidth = hairlineWidth
        outline.strokeColor = AppColors.stroke1.resolvedColor(with: traitCollection).cgColor
        setNeedsLayout()
    }

    /// Stroke path covering only this row's share of the section outline.
    private func outlinePath(lineWidth: CGFloat) -> CGPath {
        let inset = lineWidth / 2
        let left = bounds.minX + inset
        let right = bounds.maxX - inset
        let drawsTop = position == .first || position == .single
        let drawsBottom = position == .last || position == .single
        // Rails run flush to the cell edge where the neighbour continues them,
        // and pull in by half a hairline where this row caps the section.
        let top = drawsTop ? bounds.minY + inset : bounds.minY
        let bottom = drawsBottom ? bounds.maxY - inset : bounds.maxY
        guard right > left, bottom > top else { return UIBezierPath().cgPath }
        let radius = min(cardCornerRadius, (right - left) / 2, (bottom - top) / 2)

        if position == .single {
            // The whole card in one row — a plain rounded rect, so the rails
            // aren't stroked twice by the `.first` + `.last` halves.
            return UIBezierPath(
                roundedRect: CGRect(x: left, y: top, width: right - left, height: bottom - top),
                cornerRadius: radius
            ).cgPath
        }

        let path = UIBezierPath()
        if drawsTop {
            path.move(to: CGPoint(x: left, y: bottom))
            path.addLine(to: CGPoint(x: left, y: top + radius))
            path.addArc(withCenter: CGPoint(x: left + radius, y: top + radius),
                        radius: radius, startAngle: .pi, endAngle: 1.5 * .pi, clockwise: true)
            path.addLine(to: CGPoint(x: right - radius, y: top))
            path.addArc(withCenter: CGPoint(x: right - radius, y: top + radius),
                        radius: radius, startAngle: 1.5 * .pi, endAngle: 2 * .pi, clockwise: true)
            path.addLine(to: CGPoint(x: right, y: bottom))
        }
        if drawsBottom {
            path.move(to: CGPoint(x: left, y: top))
            path.addLine(to: CGPoint(x: left, y: bottom - radius))
            path.addArc(withCenter: CGPoint(x: left + radius, y: bottom - radius),
                        radius: radius, startAngle: .pi, endAngle: 0.5 * .pi, clockwise: false)
            path.addLine(to: CGPoint(x: right - radius, y: bottom))
            path.addArc(withCenter: CGPoint(x: right - radius, y: bottom - radius),
                        radius: radius, startAngle: 0.5 * .pi, endAngle: 0, clockwise: false)
            path.addLine(to: CGPoint(x: right, y: top))
        }
        if position == .middle {
            // Two bare rails, so stacked rows never double the hairline where
            // they meet — the system row separator draws the divider itself.
            path.move(to: CGPoint(x: left, y: top))
            path.addLine(to: CGPoint(x: left, y: bottom))
            path.move(to: CGPoint(x: right, y: top))
            path.addLine(to: CGPoint(x: right, y: bottom))
        }
        return path.cgPath
    }
}
