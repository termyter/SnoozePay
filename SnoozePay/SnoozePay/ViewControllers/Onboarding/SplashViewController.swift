import UIKit

/// First-frame splash — covers the gap between `LaunchScreen.storyboard` (which
/// is the system-controlled static frame iOS shows during process bring-up) and
/// the real root SceneDelegate installs (Onboarding / Permissions / TabBar).
///
/// Visual: full-screen Dawn gradient (`--sp-grad-dawn`) with the SnoozePay text
/// logo masked by the money brand gradient, mirroring the
/// `SPBalanceCard.applyValueGradient` recipe so the wordmark reads as the same
/// "money-glow" primitive used on the balance hero.
///
/// We deliberately keep `LaunchScreen.storyboard` unchanged (it is part of the
/// signing/Info.plist contract and the no-touch contract treats storyboard +
/// signing related files as PM-owned). Instead this VC is shown for ~`displayDuration`
/// before SceneDelegate calls `onFinished` and crossfades to the real root.
/// That keeps the "branded launch" outcome without touching the static
/// storyboard.
final class SplashViewController: UIViewController {

    // MARK: - Configuration

    /// How long the splash is shown after the scene becomes active before the
    /// root is replaced. 200ms matches the spec; long enough for the gradient
    /// + wordmark to register, short enough not to feel like an explicit
    /// loading screen.
    private static let displayDuration: TimeInterval = 0.20

    /// Invoked after `displayDuration` elapses. SceneDelegate uses this to
    /// crossfade into Onboarding / Permissions / TabBar depending on user
    /// state. `nil` is safe — without a callback the splash simply sits.
    var onFinished: (() -> Void)?

    // MARK: - Background (Dawn)

    /// Same 4-stop atmospheric gradient as `OnboardingViewController` so the
    /// crossfade between the two screens has no perceptible seam.
    private let dawnGradientLayer: CAGradientLayer = {
        let gradient = CAGradientLayer()
        gradient.colors = [
            UIColor(splashRGB: 0x14122A).cgColor,
            UIColor(splashRGB: 0x0F1A2E).cgColor,
            UIColor(splashRGB: 0x0A1320).cgColor,
            UIColor(splashRGB: 0x050912).cgColor
        ]
        gradient.locations = [0.0, 0.4, 0.7, 1.0]
        gradient.startPoint = CGPoint(x: 0.5, y: 0.0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1.0)
        return gradient
    }()

    // MARK: - Wordmark

    /// "SnoozePay" rendered with the money gradient mask. The label paints
    /// `clear` once `applyWordmarkGradient()` runs (same pattern as
    /// `SPBalanceCard.applyValueGradient`) so we don't double-stack the
    /// solid label colour under the gradient.
    private let wordmarkLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "SnoozePay"
        label.font = AppTypography.h1
        label.textColor = AppColors.fg1
        label.textAlignment = .center
        label.adjustsFontForContentSizeCategory = false
        return label
    }()

    /// Gradient layer that the wordmark glyphs mask — installed as a sublayer
    /// of `wordmarkLabel.layer` once layout resolves so size / theme switches
    /// re-rasterise cheaply.
    private let wordmarkGradient: CAGradientLayer = {
        let gradient = CAGradientLayer()
        gradient.colors = SPSupport.moneyGradientColors
        gradient.locations = SPSupport.moneyGradientLocations
        gradient.startPoint = SPSupport.gradientStart
        gradient.endPoint = SPSupport.gradientEnd
        return gradient
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        // Solid base under the gradient so any flash before CALayer commits
        // matches the bottom stop instead of the system bg.
        view.backgroundColor = UIColor(splashRGB: 0x050912)
        view.layer.insertSublayer(dawnGradientLayer, at: 0)
        view.addSubview(wordmarkLabel)
        NSLayoutConstraint.activate([
            wordmarkLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            wordmarkLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            wordmarkLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: view.leadingAnchor,
                constant: AppSpacing.screenInset
            ),
            wordmarkLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: view.trailingAnchor,
                constant: -AppSpacing.screenInset
            )
        ])
    }

    override var prefersStatusBarHidden: Bool { true }

    /// Force light status bar so the dark Dawn gradient reads correctly
    /// regardless of the user's system appearance.
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Disable implicit animation so size / orientation changes don't
        // crossfade the gradient stops.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dawnGradientLayer.frame = view.bounds
        CATransaction.commit()
        applyWordmarkGradient()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Schedule the handoff once the view is on-screen — viewDidLoad would
        // fire `onFinished` before the user's first frame has even composited.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.displayDuration) { [weak self] in
            self?.onFinished?()
        }
    }

    // MARK: - Wordmark gradient mask

    /// Mask `wordmarkGradient` to the rendered glyph outline — CSS equivalent
    /// of `-webkit-background-clip: text`. Lifted from
    /// `SPBalanceCard.applyValueGradient` so the visual treatment between the
    /// hero balance and the splash wordmark stays in sync.
    private func applyWordmarkGradient() {
        let textBounds = wordmarkLabel.bounds
        guard textBounds.width > 0, textBounds.height > 0 else { return }
        if wordmarkGradient.superlayer !== wordmarkLabel.layer {
            wordmarkLabel.layer.addSublayer(wordmarkGradient)
        }
        wordmarkGradient.frame = textBounds

        let renderer = UIGraphicsImageRenderer(size: textBounds.size)
        let mask = renderer.image { _ in
            (wordmarkLabel.text ?? "").draw(
                in: textBounds,
                withAttributes: [
                    .font: wordmarkLabel.font as Any,
                    .foregroundColor: UIColor.white
                ]
            )
        }
        let maskLayer = CALayer()
        maskLayer.frame = textBounds
        maskLayer.contents = mask.cgImage
        wordmarkGradient.mask = maskLayer
        wordmarkLabel.textColor = .clear
    }
}

// MARK: - Hex helper

private extension UIColor {
    /// `0xRRGGBB` literal initialiser — local copy mirroring the (private)
    /// helpers in AppColors / OnboardingViewController. File-prefixed so it
    /// can't collide with the other private extensions in the module.
    convenience init(splashRGB: UInt32, alpha: CGFloat = 1) {
        let red = CGFloat((splashRGB >> 16) & 0xFF) / 255.0
        let green = CGFloat((splashRGB >> 8) & 0xFF) / 255.0
        let blue = CGFloat(splashRGB & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}
