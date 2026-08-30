import UIKit

/// First-frame splash — V2 redesign. Covers the gap between
/// `LaunchScreen.storyboard` (signing-bound) and the real root SceneDelegate
/// installs (Onboarding / Permissions / TabBar).
///
/// Visual (V2, `docs/design/v2-handoff/components/SPMore2.jsx` lines 6-23):
/// dark `bg0` background, soft radial warm glow at centre, 96×96 rounded-rect
/// (radius 28) painted with the warn gradient and overlaid by a bell icon
/// (`bell.fill` tinted `fgOnWarn`), «SnoozePay» h1 white below, «Будильник со
/// ставкой» meta caption underneath.
///
/// `displayDuration` + `onFinished` semantics are preserved from V1 so
/// SceneDelegate keeps working unchanged.
final class SplashViewController: UIViewController {

    // MARK: - Configuration

    /// Display interval before the handoff fires. 200ms matches the original
    /// spec — long enough for the glyph + glow to register, short enough not
    /// to read as a "loading" screen.
    private static let displayDuration: TimeInterval = 0.20

    /// Invoked once `displayDuration` elapses. SceneDelegate uses this to
    /// crossfade into Onboarding / Permissions / TabBar.
    var onFinished: (() -> Void)?

    // MARK: - Layers

    /// Soft 480pt radial glow (warn 30% → transparent) centred behind the
    /// brand glyph. CSS equivalent: `radial-gradient(circle, rgba(255,184,77,
    /// .30) 0%, transparent 60%) blur(40px)`.
    private let glowLayer: CAGradientLayer = {
        let gradient = CAGradientLayer()
        gradient.type = .radial
        gradient.colors = [
            UIColor(red: 1.0, green: 184.0 / 255.0, blue: 77.0 / 255.0, alpha: 0.30).cgColor,
            UIColor(red: 1.0, green: 184.0 / 255.0, blue: 77.0 / 255.0, alpha: 0.0).cgColor
        ]
        gradient.locations = [0.0, 0.6]
        gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradient.endPoint = CGPoint(x: 1.0, y: 1.0)
        return gradient
    }()

    /// 135° warn gradient on the 96×96 brand tile (`--sp-grad-warn`).
    private let tileGradient: CAGradientLayer = {
        let gradient = CAGradientLayer()
        gradient.colors = SPSupport.warnGradientColors
        gradient.locations = SPSupport.warnGradientLocations
        gradient.startPoint = SPSupport.gradientStart
        gradient.endPoint = SPSupport.gradientEnd
        gradient.cornerRadius = AppRadius.xl  // 28pt — matches JSX
        return gradient
    }()

    // MARK: - Subviews

    /// 96×96 rounded-rect tile that hosts the bell glyph. Background paints
    /// clear because `tileGradient` is inserted at the bottom of its layer
    /// tree by `viewDidLoad` and resized in `viewDidLayoutSubviews`.
    private let tileView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        view.layer.cornerRadius = AppRadius.xl
        view.layer.masksToBounds = false
        // Warm-tinted shadow so the tile pops off the dark surface — matches
        // `boxShadow: 0 16px 48px rgba(245,158,11,.40)` from JSX. Theme-flat
        // token, so the `.cgColor` snapshot in this initializer is safe (#520).
        view.layer.shadowColor = AppColors.warnFill500.cgColor
        view.layer.shadowOpacity = 0.40
        view.layer.shadowOffset = CGSize(width: 0, height: 16)
        view.layer.shadowRadius = 24
        return view
    }()

    /// Bell icon centred inside `tileView`. SF Symbol so the tile reads
    /// crisply at any scale; size 48pt per JSX spec, tinted `fgOnWarn`.
    private let bellIconView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        let configuration = UIImage.SymbolConfiguration(pointSize: 44, weight: .semibold)
        imageView.image = UIImage(systemName: "bell.fill", withConfiguration: configuration)?
            .withRenderingMode(.alwaysTemplate)
        imageView.tintColor = AppColors.fgOnWarn
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "SnoozePay"
        label.font = AppTypography.h1
        label.textColor = .white
        label.textAlignment = .center
        label.adjustsFontForContentSizeCategory = false
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = Localized.text("onboarding.splash.subtitle")
        label.font = AppTypography.meta
        label.textColor = AppColors.fg3
        label.textAlignment = .center
        label.adjustsFontForContentSizeCategory = false
        return label
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        // Force dark — splash is always rendered against the dark canvas
        // regardless of the system theme, so the glow + tile read consistently.
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = AppColors.bg1  // #0E1320 splash canvas (#289)
        view.layer.insertSublayer(glowLayer, at: 0)
        tileView.layer.insertSublayer(tileGradient, at: 0)

        view.addSubview(tileView)
        view.addSubview(titleLabel)
        view.addSubview(subtitleLabel)
        tileView.addSubview(bellIconView)

        NSLayoutConstraint.activate([
            tileView.widthAnchor.constraint(equalToConstant: 96),
            tileView.heightAnchor.constraint(equalToConstant: 96),
            tileView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            // Stack lives optically centred — nudge slightly above geometric
            // centre so the subtitle has breathing room above the home indicator.
            tileView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -AppSpacing.sp7),

            bellIconView.centerXAnchor.constraint(equalTo: tileView.centerXAnchor),
            bellIconView.centerYAnchor.constraint(equalTo: tileView.centerYAnchor),
            bellIconView.widthAnchor.constraint(equalToConstant: 48),
            bellIconView.heightAnchor.constraint(equalToConstant: 48),

            titleLabel.topAnchor.constraint(equalTo: tileView.bottomAnchor, constant: AppSpacing.sp5),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: view.leadingAnchor,
                constant: AppSpacing.screenInset
            ),
            titleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: view.trailingAnchor,
                constant: -AppSpacing.screenInset
            ),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: AppSpacing.sp5),
            subtitleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }

    override var prefersStatusBarHidden: Bool { true }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Disable implicit animation so size/orientation changes don't
        // crossfade the gradient stops.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Position the radial glow centred on the screen; 480pt diameter
        // matches JSX so the falloff reaches roughly the upper third / lower
        // third boundary on a standard iPhone 6.1" canvas.
        let glowSize: CGFloat = 480
        glowLayer.frame = CGRect(
            x: view.bounds.midX - glowSize / 2,
            y: view.bounds.midY - glowSize / 2,
            width: glowSize,
            height: glowSize
        )
        tileGradient.frame = tileView.bounds
        tileView.layer.shadowPath = UIBezierPath(
            roundedRect: tileView.bounds,
            cornerRadius: AppRadius.xl
        ).cgPath
        CATransaction.commit()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Schedule the handoff once the view is on-screen — viewDidLoad would
        // fire `onFinished` before the user's first frame has composited.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.displayDuration) { [weak self] in
            self?.onFinished?()
        }
    }
}
