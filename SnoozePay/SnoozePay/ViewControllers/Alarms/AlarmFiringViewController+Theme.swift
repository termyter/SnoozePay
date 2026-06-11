import UIKit

/// Background + accent recipes for the alarm-firing screen, split by theme.
///
/// V3 spec (#225, `SPThemedFiring.jsx`): the alarm's theme drives the firing
/// atmosphere — full-bleed 160° gradient, radial scrim, bottom accent glow,
/// and accent tinting on the balance pill / bell tile / eyebrow / clock halo.
/// Layout, copy and CTAs are identical across all six stock themes.
///
/// `.dawn` keeps `SPDawnBackgroundView` for the background (it carries the
/// calm / tense / drained tone transitions plus the breathing sun, which the
/// static themed view intentionally doesn't replicate) but picks up the same
/// accent treatment as the other themes. `.custom(imagePath:)` replaces the
/// gradient + glow with a full-bleed user photo plus a 45% black dim and no
/// accent tinting, so the 96pt clock + warn snooze CTA stay legible against
/// arbitrary imagery.
extension AlarmFiringViewController {

    /// Install the background appropriate to the alarm's theme and resolve
    /// `firingPalette` for the accent pass. Called once from
    /// `buildFiringLayout` BEFORE the header / hero installers so they can
    /// read the palette. Falls back to Dawn if `.custom`'s on-disk file is
    /// gone (Caches purge) so the firing screen is never blank.
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
            // photo + dim. No palette: chrome stays neutral white.
            firingPalette = nil
            themeImageView.image = image
            themeImageView.isHidden = false
            themeImageDimView.isHidden = false
        } else if case .dawn = theme {
            // Default Dawn path — tone-reactive atmospheric view + the dawn
            // accent palette for the pill / bell / eyebrow / clock halo.
            firingPalette = AlarmFiringThemePalette.palette(for: .dawn)
            installDawnAtmosphericBackground()
            themeImageView.isHidden = true
            themeImageDimView.isHidden = true
        } else if let palette = AlarmFiringThemePalette.palette(for: theme) {
            // Ocean / Mountains / Forest / Neon / Abstract — static themed
            // atmosphere (160° gradient + scrim + bottom glow) per #225.
            firingPalette = palette
            let background = SPThemedFiringBackgroundView(palette: palette)
            view.insertSubview(background, at: 0)
            NSLayoutConstraint.activate([
                background.topAnchor.constraint(equalTo: view.topAnchor),
                background.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                background.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                background.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            themeImageView.isHidden = true
            themeImageDimView.isHidden = true
        } else {
            // `.custom` whose file is no longer on disk — fall back to the
            // full Dawn treatment so the screen is never blank.
            firingPalette = AlarmFiringThemePalette.palette(for: .dawn)
            installDawnAtmosphericBackground()
            themeImageView.isHidden = true
            themeImageDimView.isHidden = true
        }

        applyThemeAccents()
    }

    /// Accent pass — tint the clock halo + bell tile with the resolved
    /// palette. The balance pill and eyebrow are re-tinted on every
    /// `updateUI()` (their colour interacts with the zero-balance state), so
    /// they live in `applyThemeAccentToBalancePill()` /
    /// `updateAtmosphereTone()` instead.
    private func applyThemeAccents() {
        guard let palette = firingPalette else {
            // `.custom` photo — keep the neutral chrome and skip the bell
            // tile so the user's image stays clean.
            bellTile.isHidden = true
            return
        }
        timeLabel.layer.shadowColor = palette.timeShadowColor.cgColor
        timeLabel.layer.shadowOpacity = palette.timeShadowOpacity
        bellTile.apply(palette: palette)
        bellTile.isHidden = false
    }

    /// Re-tint the balance pill with the theme accent. The themed colours
    /// only apply while the pill is in its normal `.money` tone — at zero
    /// balance the stock pain (red) tint is a functional signal and stays
    /// un-themed in every theme. Called from `updateUI()` after
    /// `updateBalancePill()` so a tone-flip rebuild gets re-tinted too.
    func applyThemeAccentToBalancePill() {
        guard let palette = firingPalette,
              let pill = balancePill,
              pill.tone == .money else { return }
        pill.applyCustomColors(
            background: palette.pillBackground,
            border: palette.pillBorder,
            foreground: palette.accent
        )
    }
}
