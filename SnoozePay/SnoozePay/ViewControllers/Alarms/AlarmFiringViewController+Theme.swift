import UIKit

/// Background recipes for the alarm-firing screen, split out by theme.
///
/// V2 spec: the default Dawn flow uses `SPDawnBackgroundView` — a three-layer
/// atmospheric composition (base + radial overlay + breathing sun). Built-in
/// themes other than `.dawn` (Mountains, Ocean, Abstract) still ship as
/// vertical gradient backgrounds — they fall back to a single CAGradientLayer
/// installed in place of the Dawn view. `.custom(imagePath:)` replaces the
/// gradient + glow with a full-bleed user photo plus a 45% black dim so the
/// 96pt clock + warn snooze CTA stay legible against arbitrary imagery.
extension AlarmFiringViewController {

    /// Install the background appropriate to the alarm's theme. Called once
    /// from `buildFiringLayout`. Falls back to Dawn if `.custom`'s on-disk
    /// file is gone (Caches purge) so the firing screen is never blank.
    func installThemedBackground() {
        let theme = viewModel.alarm.theme

        // Mount the photo image view + dim as an always-present subview pair
        // so the +Layout subviews stack above them automatically. Hidden by
        // default; revealed only when `.custom` resolves a real on-disk file.
        view.addSubview(themeImageView)
        view.addSubview(themeImageDimView)

        NSLayoutConstraint.activate([
            themeImageView.topAnchor.constraint(equalTo: view.topAnchor),
            themeImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            themeImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            themeImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            themeImageDimView.topAnchor.constraint(equalTo: view.topAnchor),
            themeImageDimView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            themeImageDimView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            themeImageDimView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        if case .custom(let url) = theme, let image = AlarmThemeImageStore.loadImage(at: url) {
            // Custom photo path — hide the Dawn background and surface the
            // photo + dim. Don't install the dawnBackgroundView at all.
            themeImageView.image = image
            themeImageView.isHidden = false
            themeImageDimView.isHidden = false
        } else if case .dawn = theme {
            // Default Dawn path — install the V2 atmospheric view.
            installDawnAtmosphericBackground()
            themeImageView.isHidden = true
            themeImageDimView.isHidden = true
        } else {
            // Ocean / Mountains / Forest / Neon / Abstract — vertical gradient using the
            // shared `AlarmThemeRendering` stops. Built on a plain
            // SPGradientView-like CAGradientLayer hosted on a UIView so the
            // +Layout subview ordering still works.
            let gradient = CAGradientLayer()
            gradient.startPoint = CGPoint(x: 0.5, y: 0.0)
            gradient.endPoint = CGPoint(x: 0.5, y: 1.0)
            gradient.colors = AlarmThemeRendering.gradientColors(for: theme)
                ?? AlarmThemeRendering.gradientColors(for: .dawn)
            gradient.locations = AlarmThemeRendering.gradientLocations(for: theme)
                ?? AlarmThemeRendering.gradientLocations(for: .dawn)

            let container = ThemeGradientContainerView(gradient: gradient)
            container.translatesAutoresizingMaskIntoConstraints = false
            view.insertSubview(container, at: 0)
            NSLayoutConstraint.activate([
                container.topAnchor.constraint(equalTo: view.topAnchor),
                container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                container.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            themeImageView.isHidden = true
            themeImageDimView.isHidden = true
        }
    }
}

// MARK: - Plain gradient host for non-Dawn built-in themes
//
// A minimal CALayer host so the +Theme installer can drop in a gradient that
// fills bounds and reflows on layout. Lives in this file so it's not exposed
// to other VCs that don't need it.

final class ThemeGradientContainerView: UIView {
    private let gradientLayer: CAGradientLayer

    init(gradient: CAGradientLayer) {
        self.gradientLayer = gradient
        super.init(frame: .zero)
        layer.addSublayer(gradientLayer)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
    }
}
