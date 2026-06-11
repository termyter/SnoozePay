import UIKit

/// 72×72 bell tile rendered above the alarm name on the V3 themed firing
/// screen (#225).
///
/// Spec — `SPThemedFiring.jsx` lines 135–144: rounded square (r22) filled
/// with the theme's 135° `bellGrad`, a 6pt `accentSoft` ring sold via
/// `box-shadow: 0 0 0 6px`, a `0 12px 36px rgba(0,0,0,.35)` drop shadow, and
/// a 32pt stroked bell glyph at 70% black.
///
/// The view itself is 84×84 (tile + 6pt ring on every side): the ring is the
/// view's own rounded background, the gradient tile is inset 6pt inside it.
final class SPFiringBellTile: UIView {

    // MARK: - Geometry (from the JSX recipe)

    private static let tileSide: CGFloat = 72
    private static let ringWidth: CGFloat = 6
    private static let tileCornerRadius: CGFloat = 22
    static var outerSide: CGFloat { tileSide + ringWidth * 2 }

    // MARK: - Subviews

    private let tileView = UIView()
    private let gradientLayer: CAGradientLayer = {
        let gradient = CAGradientLayer()
        gradient.type = .axial
        // CSS 135° — top-left → bottom-right diagonal.
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        gradient.locations = AlarmFiringThemePalette.bellGradientLocations
        return gradient
    }()

    private let iconView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 32, weight: .medium)
        view.image = UIImage(systemName: "bell", withConfiguration: config)
        view.tintColor = UIColor.black.withAlphaComponent(0.7)
        view.contentMode = .scaleAspectFit
        return view
    }()

    // MARK: - Init

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isUserInteractionEnabled = false

        // Ring — the view's own rounded fill; radius = tile radius + ring.
        layer.cornerRadius = Self.tileCornerRadius + Self.ringWidth
        // Drop shadow lives on the ring layer, so don't mask to bounds.
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.35
        layer.shadowRadius = 18      // ≈ CSS blur 36 / 2
        layer.shadowOffset = CGSize(width: 0, height: 12)

        tileView.translatesAutoresizingMaskIntoConstraints = false
        tileView.layer.cornerRadius = Self.tileCornerRadius
        tileView.layer.masksToBounds = true
        tileView.layer.addSublayer(gradientLayer)
        addSubview(tileView)
        tileView.addSubview(iconView)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.outerSide),
            heightAnchor.constraint(equalToConstant: Self.outerSide),
            tileView.centerXAnchor.constraint(equalTo: centerXAnchor),
            tileView.centerYAnchor.constraint(equalTo: centerYAnchor),
            tileView.widthAnchor.constraint(equalToConstant: Self.tileSide),
            tileView.heightAnchor.constraint(equalToConstant: Self.tileSide),
            iconView.centerXAnchor.constraint(equalTo: tileView.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: tileView.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Palette

    /// Tint the tile with the theme's bell gradient + soft accent ring.
    /// Called by `AlarmFiringViewController+Theme` once the alarm's palette
    /// is resolved; the tile stays hidden for `.custom` photo themes.
    func apply(palette: AlarmFiringThemePalette) {
        gradientLayer.colors = palette.bellGradientColors.map { $0.cgColor }
        backgroundColor = palette.accentSoft
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.frame = tileView.bounds
        CATransaction.commit()
    }
}
