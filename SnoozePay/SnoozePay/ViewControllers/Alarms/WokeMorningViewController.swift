import UIKit

/// Morning summary screen shown immediately after the user taps
/// «Я встал — выключить» on a firing alarm (#228).
///
/// A full-screen dark screen in a single mint-green theme (regardless of the
/// alarm's firing theme): a money-gradient ✓ tile, a caps eyebrow, a headline
/// and subtitle that swap between the **clean** (snoozed 0 times) and
/// **recovered** (snoozed N times, N ₽ charged) variants, and a ghost
/// «Закрыть» button that unwinds the whole presentation stack back to the app.
///
/// Spec — `docs/design/v2-handoff/components/SPWokeMorning.jsx`. The copy /
/// variant / declension logic lives in the pure, testable `WokeMorningContent`.
final class WokeMorningViewController: UIViewController {

    // MARK: - Configuration

    private let content: WokeMorningContent
    private let onClose: () -> Void

    // MARK: - Subviews

    private let background = SPWokeMorningBackgroundView()

    /// ✓ tile — 84×84, r20, money gradient fill with a soft glow underlay.
    private let checkTile = UIView()
    private let checkTileGradient = CAGradientLayer()
    private let checkTileGlow = CAGradientLayer()
    private let checkIcon = UIImageView()

    private let eyebrowLabel = UILabel()
    private let headlineLabel = UILabel()
    private let subtitleLabel = UILabel()

    private let closeButton = SPButton(
        title: "Закрыть",
        variant: .ghost,
        size: .lg,
        fullWidth: true
    )

    /// Ordered top → bottom for the staggered entry animation.
    private var animatedElements: [UIView] { [checkTile, eyebrowLabel, headlineLabel, subtitleLabel, closeButton] }

    private var didAnimateIn = false

    // MARK: - Init

    /// - Parameters:
    ///   - snoozes: Times the user snoozed this wake. `0` selects the clean
    ///     variant; `> 0` the recovered variant.
    ///   - charged: Roubles charged across those snoozes (whole ₽ for display).
    ///   - onClose: Invoked from «Закрыть». The caller is responsible for
    ///     unwinding the full presentation stack (firing VC + this screen) —
    ///     see `AlarmFiringViewController.dismissTapped()`.
    init(snoozes: Int, charged: Double, onClose: @escaping () -> Void) {
        self.content = WokeMorningContent(snoozes: snoozes, charged: Int(charged.rounded()))
        self.onClose = onClose
        super.init(nibName: nil, bundle: nil)
        overrideUserInterfaceStyle = .dark
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(hex: 0x060F0E)
        view.accessibilityIdentifier = "woke.screen"
        closeButton.accessibilityIdentifier = "woke.closeButton"
        configureBackground()
        configureCheckTile()
        configureLabels()
        configureCloseButton()
        layout()
        // Hide the content until the entry animation drives it in.
        animatedElements.forEach { $0.alpha = 0 }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        checkTileGradient.frame = checkTile.bounds
        checkTileGlow.frame = checkTile.bounds.insetBy(dx: -30, dy: -30)
        checkTile.layer.shadowPath = UIBezierPath(
            roundedRect: checkTile.bounds,
            cornerRadius: AppRadius.lg
        ).cgPath
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didAnimateIn else { return }
        didAnimateIn = true
        animateIn()
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    // MARK: - Configuration

    private func configureBackground() {
        view.addSubview(background)
        NSLayoutConstraint.activate([
            background.topAnchor.constraint(equalTo: view.topAnchor),
            background.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            background.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    private func configureCheckTile() {
        checkTile.translatesAutoresizingMaskIntoConstraints = false
        checkTile.layer.cornerRadius = AppRadius.lg
        checkTile.layer.cornerCurve = .continuous
        // Drop shadow `0 16 48 rgba(46,219,159,.45)`.
        checkTile.layer.shadowColor = AppColors.money400.cgColor
        checkTile.layer.shadowOpacity = 0.45
        checkTile.layer.shadowOffset = CGSize(width: 0, height: 16)
        checkTile.layer.shadowRadius = 24

        // Soft outer glow underlay (`radial accent .42 → clear`), behind the tile.
        checkTileGlow.type = .radial
        checkTileGlow.colors = [
            AppColors.money400.withAlphaComponent(0.42).cgColor,
            UIColor.clear.cgColor
        ]
        checkTileGlow.locations = [0.0, 0.7]
        checkTileGlow.startPoint = CGPoint(x: 0.5, y: 0.5)
        checkTileGlow.endPoint = CGPoint(x: 1.0, y: 1.0)
        checkTile.layer.addSublayer(checkTileGlow)

        // Money gradient fill.
        checkTileGradient.colors = SPSupport.moneyGradientColors
        checkTileGradient.locations = SPSupport.moneyGradientLocations
        checkTileGradient.startPoint = SPSupport.gradientStart
        checkTileGradient.endPoint = SPSupport.gradientEnd
        checkTileGradient.cornerRadius = AppRadius.lg
        checkTile.layer.addSublayer(checkTileGradient)

        let config = UIImage.SymbolConfiguration(pointSize: 44, weight: .bold)
        checkIcon.image = UIImage(systemName: "checkmark", withConfiguration: config)
        checkIcon.tintColor = .white
        checkIcon.contentMode = .scaleAspectFit
        checkIcon.translatesAutoresizingMaskIntoConstraints = false
        checkTile.addSubview(checkIcon)

        NSLayoutConstraint.activate([
            checkTile.widthAnchor.constraint(equalToConstant: 84),
            checkTile.heightAnchor.constraint(equalToConstant: 84),
            checkIcon.centerXAnchor.constraint(equalTo: checkTile.centerXAnchor),
            checkIcon.centerYAnchor.constraint(equalTo: checkTile.centerYAnchor)
        ])
    }

    private func configureLabels() {
        eyebrowLabel.attributedText = NSAttributedString(
            string: WokeMorningContent.eyebrow,
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: UIColor(hex: 0x7CE0B9)
            ]
        )
        eyebrowLabel.textAlignment = .center
        eyebrowLabel.numberOfLines = 0
        eyebrowLabel.translatesAutoresizingMaskIntoConstraints = false

        headlineLabel.text = content.headline
        headlineLabel.font = AppFonts.sans(.medium, 28)
        headlineLabel.textColor = .white
        headlineLabel.textAlignment = .center
        headlineLabel.numberOfLines = 0
        headlineLabel.translatesAutoresizingMaskIntoConstraints = false

        subtitleLabel.text = content.subtitle
        subtitleLabel.font = AppFonts.sans(.regular, 15)
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.62)
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureCloseButton() {
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        // Green outline per spec — border 1pt rgba(124,224,185,.45).
        closeButton.ghostBorderOverride = (
            1,
            UIColor(red: 124 / 255, green: 224 / 255, blue: 185 / 255, alpha: 0.45)
        )
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
    }

    private func layout() {
        // Centred content column: ✓ tile + eyebrow + headline + subtitle.
        let column = UIStackView(arrangedSubviews: [
            checkTile,
            eyebrowLabel,
            headlineLabel,
            subtitleLabel
        ])
        column.axis = .vertical
        column.alignment = .center
        column.spacing = AppSpacing.sp3
        column.setCustomSpacing(26, after: checkTile)     // eyebrow mt 26
        column.setCustomSpacing(AppSpacing.sp3, after: eyebrowLabel)  // headline mt 14 (≈12)
        column.setCustomSpacing(AppSpacing.sp3, after: headlineLabel) // subtitle mt 14
        column.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(column)
        view.addSubview(closeButton)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            // Column centred vertically in the space above the button.
            column.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            column.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: AppSpacing.sp6),
            column.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -AppSpacing.sp6),

            // Headline maxWidth 320, subtitle maxWidth 300 — centred wrap.
            headlineLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 320),
            subtitleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 300),

            // Bottom «Закрыть» — full width within the screen inset (padding 24).
            closeButton.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: AppSpacing.sp6),
            closeButton.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -AppSpacing.sp6),
            closeButton.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -AppSpacing.sp7)
        ])
    }

    // MARK: - Entry animation

    /// Fade + translateY 18 → 0, 600ms `cubic-bezier(.2,.8,.2,1)`, staggered
    /// 0 / 80 / 160 / 240 / 320ms across the 5 content elements. Driven with
    /// `UIView` keyframe animations + a `CAMediaTimingFunction` to match the
    /// JSX easing exactly.
    private func animateIn() {
        let timing = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
        for (index, element) in animatedElements.enumerated() {
            element.alpha = 0
            element.transform = CGAffineTransform(translationX: 0, y: 18)
            let delay = TimeInterval(index) * 0.08
            CATransaction.begin()
            CATransaction.setAnimationTimingFunction(timing)
            UIView.animate(
                withDuration: 0.6,
                delay: delay,
                options: [.allowUserInteraction],
                animations: {
                    element.alpha = 1
                    element.transform = .identity
                }
            )
            CATransaction.commit()
        }
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        onClose()
    }
}

// MARK: - Hex helper (file-scoped)

private extension UIColor {
    /// `0xRRGGBB` literal initializer for this screen's mint accent / base
    /// colours. File-scoped — `private` is file-scope in Swift; the brand-token
    /// `UIColor(hex:)` in AppColors is `private` and not visible across files.
    convenience init(hex rgb: UInt32, alpha: CGFloat = 1) {
        let red = CGFloat((rgb >> 16) & 0xFF) / 255.0
        let green = CGFloat((rgb >> 8) & 0xFF) / 255.0
        let blue = CGFloat(rgb & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}
