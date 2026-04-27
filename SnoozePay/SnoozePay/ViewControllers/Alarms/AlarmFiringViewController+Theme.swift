import UIKit

/// Background recipes for the alarm-firing screen, split out by theme (#151).
///
/// The default Dawn flow stays exactly as #138 — vertical 4-stop gradient with
/// the warm radial glow breathing below it. Built-in themes (Mountains,
/// Ocean, Abstract) swap the gradient stops while keeping the rest of the
/// screen identical. `.custom(imagePath:)` replaces the gradient + glow with
/// a full-bleed user photo plus a 45% black dim so the 96pt clock + warn
/// snooze CTA stay legible.
extension AlarmFiringViewController {

    /// Install the background appropriate to the alarm's theme. Called once
    /// from `setupUI`. Falls back to Dawn if `.custom`'s on-disk file is
    /// gone (Caches purge) so the firing screen is never blank.
    func installThemedBackground() {
        let theme = viewModel.alarm.theme

        // Always insert the gradient + glow at the bottom of the layer tree
        // so they sit beneath any subsequently added content. The image view
        // and its dim are added as subviews so they stack above the gradient
        // automatically.
        view.layer.insertSublayer(themeGradientLayer, at: 0)
        view.layer.insertSublayer(warmGlowLayer, at: 1)
        view.insertSubview(themeImageView, at: 0)
        view.insertSubview(themeImageDimView, aboveSubview: themeImageView)

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
            themeImageView.image = image
            themeImageView.isHidden = false
            themeImageDimView.isHidden = false
            // Hide the gradient + warm glow — the photo is the background of
            // record and we don't want the amber halo bleeding through.
            themeGradientLayer.isHidden = true
            warmGlowLayer.isHidden = true
        } else {
            // Built-in (or .custom with missing file) → vertical gradient.
            // Default to Dawn when the gradient lookup misses (defensive —
            // every built-in case currently returns colours).
            let resolved: AlarmTheme = {
                if case .custom = theme { return .dawn }
                return theme
            }()
            themeGradientLayer.colors = AlarmThemeRendering.gradientColors(for: resolved)
                ?? AlarmThemeRendering.gradientColors(for: .dawn)
            themeGradientLayer.locations = AlarmThemeRendering.gradientLocations(for: resolved)
                ?? AlarmThemeRendering.gradientLocations(for: .dawn)
            themeGradientLayer.isHidden = false
            themeImageView.isHidden = true
            themeImageDimView.isHidden = true
        }
    }
}
