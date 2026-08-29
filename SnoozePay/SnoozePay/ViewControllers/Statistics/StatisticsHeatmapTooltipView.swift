import UIKit

/// Tooltip from artboard 27a — bg3 bubble with a hairline border, drop
/// shadow, an upward arrow, the date headline and a swatch + status line.
final class HeatmapTooltipView: UIView {

    /// Bubble padding from artboard 27a — 10/14, i.e. deliberately off the
    /// 4pt grid so the two-line bubble stays compact next to a 40pt cell.
    private static let verticalPadding: CGFloat = 10
    private static let horizontalPadding: CGFloat = 14
    /// Gap between the swatch, the status word and the amount.
    private static let statusRowSpacing: CGFloat = 6
    private static let swatchSide: CGFloat = 8
    private static let arrowSide: CGFloat = 12

    private let arrowView = UIView()
    private let dateLabel = UILabel()
    private let swatchView = UIView()
    /// Gradient fill for the swatch so it matches the tapped cell's gradient
    /// (#289). Hidden for `.empty`, where the flat tone is used instead.
    private let swatchGradient = CAGradientLayer()
    private let statusLabel = UILabel()
    private let spentLabel = UILabel()
    private var status: StatisticsViewModel.DayStatus = .empty

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure() {
        backgroundColor = AppColors.bg3
        layer.cornerRadius = AppRadius.sm
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        isUserInteractionEnabled = false

        arrowView.backgroundColor = AppColors.bg3
        arrowView.layer.borderWidth = 1
        arrowView.transform = CGAffineTransform(rotationAngle: .pi / 4)
        addSubview(arrowView)
        refreshChrome()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: HeatmapTooltipView, _) in
            view.refreshChrome()
        }

        dateLabel.font = AppFonts.sans(.bold, 14)
        dateLabel.textColor = AppColors.fg1
        dateLabel.translatesAutoresizingMaskIntoConstraints = false

        swatchView.layer.cornerRadius = AppSpacing.sp1 / 2
        swatchView.layer.masksToBounds = true
        swatchView.translatesAutoresizingMaskIntoConstraints = false
        swatchGradient.startPoint = SPSupport.gradientStart
        swatchGradient.endPoint = SPSupport.gradientEnd
        swatchView.layer.insertSublayer(swatchGradient, at: 0)

        statusLabel.font = AppFonts.sans(.semibold, 12)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        spentLabel.font = AppFonts.sans(.medium, 12)
        spentLabel.textColor = AppColors.fg3
        spentLabel.translatesAutoresizingMaskIntoConstraints = false

        let statusRow = UIStackView(arrangedSubviews: [swatchView, statusLabel, spentLabel])
        statusRow.axis = .horizontal
        statusRow.alignment = .center
        statusRow.spacing = Self.statusRowSpacing
        statusRow.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [dateLabel, statusRow])
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = AppSpacing.sp1
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            swatchView.widthAnchor.constraint(equalToConstant: Self.swatchSide),
            swatchView.heightAnchor.constraint(equalToConstant: Self.swatchSide),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: Self.verticalPadding),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.verticalPadding),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.horizontalPadding),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.horizontalPadding)
        ])
    }

    /// Re-resolve every CALayer colour the bubble owns. The border is a
    /// hairline `whiteOverlay08` (near-black ink on light, white on dark) and
    /// the drop shadow is `shadow2` — the floating-surface recipe, which on
    /// light is `rgba(8,14,30,.10)` rather than the 50% black this used to
    /// hardcode. Half-black over a white card printed a grey smear instead of
    /// a shadow.
    private func refreshChrome() {
        let border = AppColors.whiteOverlay08.resolvedColor(with: traitCollection).cgColor
        layer.borderColor = border
        arrowView.layer.borderColor = border
        AppShadow.shadow2(for: traitCollection).apply(to: layer)
        refreshSwatch()
    }

    func apply(_ tooltip: StatisticsViewModel.HeatmapTooltip) {
        dateLabel.text = tooltip.dateText
        statusLabel.text = tooltip.statusText
        statusLabel.textColor = StatisticsHeatmapView.toneColor(for: tooltip.status)
        status = tooltip.status
        refreshSwatch()
        spentLabel.text = tooltip.spentText
        spentLabel.isHidden = tooltip.spentText == nil
    }

    /// Swatch mirrors the tapped cell, so it carries the same frozen-CGColor
    /// problem the grid does — resolved against this view's traits, refreshed
    /// on a theme flip.
    private func refreshSwatch() {
        traitCollection.performAsCurrent {
            if let stops = StatisticsHeatmapView.gradientStops(for: status) {
                swatchGradient.isHidden = false
                swatchGradient.colors = stops.colors
                swatchGradient.locations = stops.locations
                swatchView.backgroundColor = .clear
            } else {
                swatchGradient.isHidden = true
                swatchView.backgroundColor = StatisticsHeatmapView.toneColor(for: status)
            }
        }
    }

    /// Positions the upward arrow so it points at the tapped cell even when
    /// the bubble itself is clamped to the grid edges.
    func setArrowCenterX(_ centerX: CGFloat) {
        let side = Self.arrowSide
        let clamped = max(side, min(centerX, bounds.width - side))
        arrowView.frame = CGRect(x: clamped - side / 2, y: -side / 2, width: side, height: side)
        arrowView.transform = CGAffineTransform(rotationAngle: .pi / 4)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Keep the shadow path in sync so the arrow doesn't cast a hole.
        layer.shadowPath = UIBezierPath(
            roundedRect: bounds,
            cornerRadius: layer.cornerRadius
        ).cgPath
        swatchGradient.frame = swatchView.bounds
    }
}
