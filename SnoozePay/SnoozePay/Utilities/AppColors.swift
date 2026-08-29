import UIKit

/// App-wide color tokens. The "money / pain / warn" scales are the SnoozePay
/// brand palette (see `docs/design/snoozepay-2026-04-27/project/tokens.css`);
/// the legacy `accentGreen` / `accentOrange` / `snoozeButton` aliases at the
/// bottom map onto the new scales so existing screens keep compiling until
/// each one is migrated in its own UI issue.
///
/// Nothing here resolves to a *system* colour, and `AppColorsSurfaceRampTests`
/// keeps it that way: the system palette has its own values (`#F2F2F7`,
/// `#1C1C1E`, …) that appear nowhere in `tokens.css`, so a token backed by one
/// is a token that silently disagrees with the design canon.
enum AppColors {
    // Surfaces are `bg0`...`bg4` and foregrounds are `fg1`...`fg4`, both
    // further down. The pre-token aliases that used to sit here
    // (`background`, `surface`, `surface2`, `textPrimary`, `textSecondary`,
    // `textTertiary`) were the palette's last references to the *system*
    // colours, and system colours cannot be canon: `secondarySystemBackground`
    // is `#F2F2F7` / `#1C1C1E`, neither of which is a value in `tokens.css`.
    // They are gone (#527) — reach for the token that names the role.

    // MARK: - Brand accent scales (theme-aware)
    //
    // The dark values are the brand palette from `tokens.css`. The light ones
    // are *derived* from them — same hue, reduced value — because the dark
    // scale cannot simply carry over: it was picked to glow on `#060912`, and
    // on a light surface it stops being readable. Measured contrast of the
    // dark values on the light raised card (`bg2` = `#ECEEF6`):
    //
    //     money500 2.19    money600 2.99    money700 4.61
    //     pain500  2.96    pain600  4.09
    //     warn500  1.85    warn600  2.89
    //     info500  2.80
    //
    // So "shift one or two steps darker" does not work — of the whole existing
    // palette exactly one value (`money700`) clears 4.5:1 on a light card. Each
    // light step below is instead solved for its ROLE: 300 ≈ 3:1 (decorative /
    // borders), 400 ≈ 4.5:1 (large text), 500 ≈ 6:1 (body text), 600 ≈ 8:1,
    // 700 ≈ 10.5:1.
    //
    // Contrast is solved against `bg2`, not `bg0`: accents sit on cards far
    // more often than on the app background, and `bg2` is the worse surface in
    // BOTH themes (lighter than `bg0` on dark, darker than `bg0` on light). A
    // value that clears there clears everywhere. `AppColorsContrastTests` pins
    // this — it fails if any step drops below its role's threshold.
    //
    // Canvas with the full comparison and the reasoning: see #474.

    // MARK: - Brand · Money (positive / earnings / "deposit recovered")
    static let money300 = dynamicColor(dark: 0x5EEAB8, light: 0x0E9C6D)
    static let money400 = dynamicColor(dark: 0x2EDB9F, light: 0x0B7B56)
    /// Primary money tone — used for the deposit / balance hero.
    static let money500 = dynamicColor(dark: 0x10B981, light: 0x096647)
    static let money600 = dynamicColor(dark: 0x0E9D6E, light: 0x075139)
    static let money700 = dynamicColor(dark: 0x0B7A56, light: 0x053D2B)

    // MARK: - Brand · Pain (progressive snooze / penalty / loss)
    static let pain300 = dynamicColor(dark: 0xFFB4A8, light: 0xF2513F)
    static let pain400 = dynamicColor(dark: 0xFF7A6B, light: 0xC04032)
    /// Default "progressive snooze charged" red.
    static let pain500 = dynamicColor(dark: 0xF4523F, light: 0x9F3529)
    static let pain600 = dynamicColor(dark: 0xD43A28, light: 0x7E2B21)

    // MARK: - Brand · Warn INK (tones that must out-contrast the PAGE)
    //
    // The light scale is bronze, not amber: amber on a light card is 1.85:1 and
    // cannot carry text at any step of the ramp. Since #520 this half of the
    // warn role is named explicitly — these are the tones whose job is to be
    // read *against* the surface behind them, i.e. text and borders. Anything
    // that is itself a surface takes `warnFill*` below.
    static let warn300 = dynamicColor(dark: 0xFFD479, light: 0xBE7B09)
    static let warn400 = dynamicColor(dark: 0xFFB84D, light: 0x966107)
    /// Warn body-text tone. 6.03:1 on the light raised card, 7.89:1 on the dark one.
    static let warn500 = dynamicColor(dark: 0xF59E0B, light: 0x7C5006)
    static let warn600 = dynamicColor(dark: 0xC97A06, light: 0x634004)

    // MARK: - Brand · Warn FILL (amber SURFACES — the other half of the role)
    //
    // `tokens.css` declares the warn ramp once in the base `:root`
    // (`--sp-warn-500: #F59E0B`) and never overrides it inside
    // `[data-theme="light"]` (:79-112 redefines bg / fg / stroke / shadow only).
    // By canon a warn *fill* is therefore amber in BOTH themes, and these
    // constants are flat rather than `dynamicColor` for that reason.
    //
    // Why the split had to happen (#520): the snooze-duration track took the
    // ink tone, so in light it rendered `#7C5006` against a `money500` `#096647`
    // thumb — **1.00:1, exactly isoluminant.** Filled and unfilled halves
    // differed only in hue, and the control read as one smudge. On the canon
    // amber the same pair measures 3.26:1.
    //
    // Which half a call site wants is decided by what the colour has to
    // out-contrast, not by what it looks like:
    //
    //     surface under ink  → warnFill*   track, chip, tile, wash, shadow, gradient
    //     read against page  → warn*       label text, and BORDERS
    //
    // Borders are the counter-intuitive one and stay on the ink scale: the
    // `SPAlarmBackendBanner` edge #538 bought measures 3.71:1 as bronze over the
    // light page and would collapse to 1.69:1 as amber. A stroke is ink shaped
    // like a rectangle.
    //
    // Being flat also removes these from the `CGColor`-baking class (#531/#538/
    // #552/#553): a colour that does not vary by trait has nothing to re-resolve
    // when the theme flips under a `CAGradientLayer` or a `layer.shadowColor`.
    /// Lightest stop of `--sp-grad-warn`.
    static let warnFill300 = UIColor(hex: 0xFFD479)
    /// Primary warn surface — `--sp-warn-500`. Ink on it is `fgOnWarn` (8.79:1).
    static let warnFill500 = UIColor(hex: 0xF59E0B)
    /// Darkest stop of `--sp-grad-warn`.
    static let warnFill600 = UIColor(hex: 0xC97A06)

    // MARK: - Brand · Info
    /// Informational links only — `--sp-info-500` in `tokens.css`.
    static let info500 = dynamicColor(dark: 0x4F8BFF, light: 0x3257A1)

    // MARK: - Theme-aware surfaces (`bg0`...`bg4`)
    //
    // Five-step surface elevation per `tokens.css`. `bg0` is the deepest /
    // app background, `bg4` the top hover/focus surface. Values resolve via
    // `UIColor(dynamicProvider:)` so each token auto-adapts when the system
    // toggles between light and dark, *and* when a single VC overrides its
    // `userInterfaceStyle` (e.g. AlarmFiringViewController forcing dark).
    /// App background — deepest. Dark `#060912`, Light `#F4F6FB`.
    static let bg0 = dynamicColor(dark: 0x060912, light: 0xF4F6FB)
    /// Card / sheet base. Dark `#0E1320`, Light `#FFFFFF`.
    static let bg1 = dynamicColor(dark: 0x0E1320, light: 0xFFFFFF)
    /// Raised card. Dark `#161C2E`, Light `#ECEEF6`.
    static let bg2 = dynamicColor(dark: 0x161C2E, light: 0xECEEF6)
    /// Fill of a **raised** surface — the semantic token `SPCard(tone:
    /// .raised)` and the enabled alarm row ask for, as opposed to the raw
    /// `bg2` ramp step they used to hardcode.
    ///
    /// The `bg` ramp does not mean the same thing in both themes. In dark it
    /// is a height ladder: every step is lighter than the page, so `bg2`
    /// (`#161C2E`) reads as *above* `bg1` (`#0E1320`) on `bg0` (`#060912`).
    /// In light the page is already near-white — `bg1` (`#FFFFFF`) *is* the
    /// card, and `bg2` (`#ECEEF6`) sits **below** `bg0` (`#F4F6FB`): it is a
    /// recessed tone, not a raised one. Mapping `.raised` onto `bg2`
    /// unconditionally therefore inverts elevation in exactly one theme of
    /// two, and wherever a pair of tones encodes state — enabled vs disabled
    /// alarm rows — the meaning flips with it: the switched-OFF alarm was the
    /// brightest card on the light list (#543).
    ///
    /// So light keeps the white card and lets `--sp-shadow-2` carry the
    /// height (shadow is what elevation is made of on a white page); dark
    /// keeps the ramp step it always had, and does not move.
    ///
    /// Ordering is pinned by `SPCardElevationOrderTests`, which measures the
    /// *pair* rather than either fill on its own.
    static let bgRaised = UIColor { trait in
        trait.userInterfaceStyle == .light
            ? AppColors.bg1.resolvedColor(with: trait)
            : AppColors.bg2.resolvedColor(with: trait)
    }
    /// Active chip / sheet header. Dark `#1F2740`, Light `#DFE3F0`.
    static let bg3 = dynamicColor(dark: 0x1F2740, light: 0xDFE3F0)
    /// Hover / focus surface. Dark `#2A3354`, Light `#C9D0E3`.
    static let bg4 = dynamicColor(dark: 0x2A3354, light: 0xC9D0E3)

    // MARK: - Theme-aware foregrounds (`fg1`...`fg4`)
    //
    // Primary → disabled scale. Dark mode tints `#EBEDF5` (near-white) at
    // 1.0 / 0.86 / 0.58 / 0.32 alpha; light mode tints `#0A0F1F` (brand
    // near-black ink) at 1.0 / 0.82 / 0.56 / 0.32. Step scale matches
    // `tokens.css`.
    /// Primary headings & hero numbers.
    static let fg1 = foreground(darkAlpha: 1.0, lightAlpha: 1.0, darkIsPureWhite: true)
    /// Body copy. Dark 86% white-ish, Light 82% near-black.
    static let fg2 = foreground(darkAlpha: 0.86, lightAlpha: 0.82)
    /// Meta. Dark 58%, Light 56%.
    static let fg3 = foreground(darkAlpha: 0.58, lightAlpha: 0.56)
    /// Disabled / placeholder. Dark 32%, Light 32%.
    static let fg4 = foreground(darkAlpha: 0.32, lightAlpha: 0.32)

    /// Text rendered ON top of `money500` fills. Dark mint ink on the bright
    /// dark-theme fill; white on the light theme's dark-green fill, which is
    /// far too dark to carry the mint ink (`#052016` on `#096647` is 1.5:1).
    static let fgOnMoney = dynamicColor(dark: 0x052016, light: 0xFFFFFF)
    /// Text rendered ON top of `pain500` fills — white in both themes.
    static let fgOnPain = UIColor.white
    /// Text rendered ON top of `warnFill*` surfaces — `--sp-fg-on-warn`, which
    /// `tokens.css` declares once and does not override in light either.
    ///
    /// Deliberately NOT an inversion pair like `fgOnMoney`. It used to be, and
    /// the comment here used to explain that the light `warn500` was bronze and
    /// so took white ink. That reasoning died with #520: the fill under this ink
    /// is amber in both themes now, and white on amber is **2.15:1** — the same
    /// failure the split exists to remove, just moved onto the label. The value
    /// below measures **8.79:1** on `warnFill500`.
    static let fgOnWarn = UIColor(hex: 0x1A0F00)

    // MARK: - Deep promo fill (referral hero)
    //
    // The referral hero is a *filled* promo panel, not a surface: it stays
    // DARK in both themes, the same way `--sp-grad-night` / `--sp-grad-dawn`
    // keep their night values inside the light block of `tokens.css`. The dark
    // stops are the canon literals inlined in `SPMore4.jsx`
    // (`#1A2810 → #2C4A1F → #4F8A3A`) and do not move. The light stops are the
    // light money ramp read deep-to-bright (`money700 → money600 → money400`),
    // so the panel keeps the same "deep green, brightening toward the
    // bottom-right" shape while sitting on a near-white page instead of
    // becoming a white card that its white copy would disappear into.
    /// Deepest stop — gradient origin (top-left), where the copy sits.
    static let heroDeep700 = dynamicColor(dark: 0x1A2810, light: 0x053D2B)
    /// Middle stop.
    static let heroDeep500 = dynamicColor(dark: 0x2C4A1F, light: 0x075139)
    /// Brightest stop — gradient end (bottom-right), decorative only.
    static let heroDeep300 = dynamicColor(dark: 0x4F8A3A, light: 0x0B7A56)
    /// Ink on `heroDeep*` — white in BOTH themes, because unlike `money500`
    /// this fill is dark on light too. Not interchangeable with `fgOnMoney`:
    /// that token's dark-theme mint ink would vanish into the deep-green panel.
    static let fgOnHeroDeep = UIColor.white

    // MARK: - Payment instrument card (Apple Pay tile)
    //
    // Same class as `heroDeep*`: a *filled* panel, not a surface, so it does
    // NOT flip with the theme. The canon calls it «чёрная карточка а-ля iOS
    // Wallet» (`SPMore3.jsx` L549) and iOS Wallet keeps a dark instrument dark
    // on a white page — flipping this fill to `bg1` in light would turn a
    // payment card into an app card and lose the metaphor the screen is built
    // on. Measured against the page: 1.09:1 on dark `bg0` (the canon leans on
    // the rim, not the fill) and 16.83:1 on light `bg0`.
    /// Apple Pay card fill — `#15151A` in BOTH themes.
    static let paymentCard = UIColor(hex: 0x15151A)
    /// Glassy rim of `paymentCard`. Deliberately NOT `stroke1`: that token is
    /// near-black ink in light and would disappear into the dark card. Static
    /// white, so `.cgColor` on it needs no trait re-resolution.
    static let paymentCardEdge = UIColor(white: 1.0, alpha: 0.10)
    /// Primary ink on `paymentCard` — the Apple glyph and the "Pay" wordmark.
    /// 18.2:1 in both themes. Not interchangeable with `fg1`, which is
    /// near-black ink in light and would vanish here.
    static let fgOnPaymentCard = UIColor.white
    /// Secondary ink on `paymentCard` — caps state labels and meta copy.
    /// 5.28:1. The canon carried two steps here (50% and 40% white); the 40%
    /// one measured 3.83:1 and failed AA for 12pt caps in BOTH themes, so the
    /// pair collapses onto the step that passes.
    static let fgOnPaymentCardMeta = UIColor(white: 1.0, alpha: 0.5)

    // MARK: - Warn wash (tinted chip — NOT a solid fill)
    //
    // `fgOnWarn` is ink for a SOLID `warn500` fill. A *wash* — the brand colour
    // laid at partial alpha over a card — is a different surface and needs
    // different ink: white on a wash measures ~1.2:1, the defect fixed in
    // `SPAlarmBackendBanner`. The wash inverts between themes: a deep 60%
    // bronze over the dark card, a faint 18% tint (the `SPPill` strength) over
    // the light one, so the ink can be dark bronze instead of white.
    /// Warn-tinted chip fill — the avatar of a friend mid-streak.
    static let warnWash = UIColor { trait in
        let base = AppColors.warn600.resolvedColor(with: trait)
        return base.withAlphaComponent(trait.userInterfaceStyle == .light ? 0.18 : 0.60)
    }
    /// Ink on `warnWash`. `warn300` glows on the deep dark wash; the pale light
    /// wash takes `warn600`, the darkest bronze in the scale.
    static let fgOnWarnWash = UIColor { trait in
        trait.userInterfaceStyle == .light
            ? AppColors.warn600.resolvedColor(with: trait)
            : AppColors.warn300.resolvedColor(with: trait)
    }

    /// Ink on a *pain*-tinted wash — same shape as `fgOnWarnWash`, and needed
    /// for the same reason. The zero-balance pill on the alarms list lays a
    /// `pain500` gradient at 10%→2% over the page; `pain300` glows on that in
    /// dark (10.82:1) but measures **2.77:1** in light, because the light
    /// `pain300` is a bright coral on a near-white wash. The light branch takes
    /// `pain600`, the darkest tone in the scale (7.41:1). Not interchangeable
    /// with `fgOnPain`, which is ink for a SOLID `pain500` fill.
    static let fgOnPainWash = UIColor { trait in
        trait.userInterfaceStyle == .light
            ? AppColors.pain600.resolvedColor(with: trait)
            : AppColors.pain300.resolvedColor(with: trait)
    }

    // MARK: - Transient overlay (toast / snackbar)
    //
    // A toast is not a card. It floats over arbitrary content for 1.5s, so it
    // has no fixed page relationship to lean on, and it cannot be solved by
    // reaching for a higher step of the surface ramp: measured against the app
    // background (`bg0`), the whole ramp is flat.
    //
    //     light   bg1 1.08   bg2 1.07   bg3 1.19   bg4 1.43
    //     dark    bg1 1.07   bg2 1.17   bg3 1.35   bg4 1.61
    //
    // Not one step reaches the 3:1 that WCAG 1.4.11 asks of a UI surface —
    // which is why the pill shipped at 1.19:1 in light (#518), and why the
    // recipe before it failed the same way in dark (#496). Two attempts inside
    // the ramp, two failures; the ramp is the wrong tool.
    //
    // So the toast takes the INVERSE surface — a dark pill on the light page,
    // a light pill on the dark one, the standard snackbar shape — which
    // measures ~17:1 in both themes. The border and the lift stay (see
    // `SettingsToastLabel`), but they are now decoration rather than the only
    // thing holding the pill together.
    /// Toast pill fill. Inverse of the page: the brand near-black ink in
    /// light, the near-white foreground base in dark.
    static let toastSurface = dynamicColor(dark: 0xEBEDF5, light: 0x0A0F1F)
    /// Ink on `toastSurface`. Flips *with* the fill, so it must not be swapped
    /// for `fg1`: `fg1` is ink for a normal surface, and on the inverse pill it
    /// lands same-on-same — exactly the 1.24:1 defect of #496.
    static let fgOnToast = dynamicColor(dark: 0x0A0F1F, light: 0xEBEDF5)
    /// Rim of the toast pill — `stroke2` mirrored, for the same reason the fill
    /// is: on the light theme's dark pill the hairline has to be white, and on
    /// the dark theme's light pill near-black. Using `stroke2` directly would
    /// paint near-black ink onto a near-black pill.
    static let toastEdge = UIColor { trait in
        let mirrored: UIUserInterfaceStyle = trait.userInterfaceStyle == .light ? .dark : .light
        return AppColors.stroke2.resolvedColor(with: UITraitCollection(userInterfaceStyle: mirrored))
    }

    // MARK: - Theme-aware overlays (alpha on white / near-black ink)
    //
    // Dark mode lays white over surfaces (`rgba(255,255,255,X)`); light mode
    // lays the near-black ink (`#080E1E`) at the same alpha so an overlay
    // chip "darkens" on light and "brightens" on dark.
    static let whiteOverlay04 = overlay(alpha: 0.04)
    static let whiteOverlay06 = overlay(alpha: 0.06)
    static let whiteOverlay08 = overlay(alpha: 0.08)
    static let whiteOverlay12 = overlay(alpha: 0.12)
    static let whiteOverlay16 = overlay(alpha: 0.16)
    static let whiteOverlay24 = overlay(alpha: 0.24)

    // MARK: - Theme-aware strokes
    //
    // 1px hairlines for cards and dividers. Same alpha values, opposite ink:
    // white on dark / near-black on light.
    /// 8% hairline.
    static let stroke1 = overlay(alpha: 0.08)
    /// 14% stronger hairline (active state, focus ring).
    static let stroke2 = overlay(alpha: 0.14)
    /// Money-tinted stroke. Dark 45% / Light 55% (per `tokens.css`).
    static let strokeMoney = UIColor { trait in
        let alpha: CGFloat = trait.userInterfaceStyle == .light ? 0.55 : 0.45
        return UIColor(red: 46.0 / 255.0, green: 219.0 / 255.0, blue: 159.0 / 255.0, alpha: alpha)
    }
    /// Pain-tinted stroke. Dark 45% / Light 55%.
    static let strokePain = UIColor { trait in
        let alpha: CGFloat = trait.userInterfaceStyle == .light ? 0.55 : 0.45
        return UIColor(red: 244.0 / 255.0, green: 82.0 / 255.0, blue: 63.0 / 255.0, alpha: alpha)
    }

    // MARK: - Legacy aliases
    //
    // Existing screens reach for these names. Each one is now a thin alias on
    // top of the brand scales, so a future PR can grep-and-replace call sites
    // without changing the rendered colour.

    /// Legacy green accent → maps onto the new `money500`.
    static let accentGreen = money500
    /// Legacy orange accent → maps onto the new `warn500`.
    static let accentOrange = warn500
    /// Destructive red → maps onto the new `pain500`.
    static let destructiveRed = pain500

    // MARK: - Button states (legacy)
    /// Snooze button amber → `warnFill500`. A button is a surface, so this
    /// alias follows the fill half of the warn role, not the ink half (#520).
    static let snoozeButton = warnFill500
    /// Dismiss button green → `money500`.
    static let dismissButton = money500

    /// Warm gold used for the active "Поспать ещё" pill on the alarm-firing
    /// screen (#E8A838). Kept as its own literal because the firing UI uses a
    /// slightly warmer hue than `warn500` (#79); migrating it onto a brand
    /// token is its own UI-issue decision.
    static let alarmFiringSnooze = UIColor(red: 0.91, green: 0.66, blue: 0.22, alpha: 1) // #E8A838

    // MARK: - Theme-aware helpers

    /// Resolve a token to either the light or dark hex literal based on the
    /// current trait collection. Used for the surface scale.
    private static func dynamicColor(dark: UInt32, light: UInt32) -> UIColor {
        UIColor { trait in
            trait.userInterfaceStyle == .light ? UIColor(hex: light) : UIColor(hex: dark)
        }
    }

    /// Resolve a foreground token. Dark mode tints `#EBEDF5` (or pure white
    /// for `fg1`) at `darkAlpha`; light mode tints the brand near-black ink
    /// `#0A0F1F` at `lightAlpha`. Pure white in dark is needed only for
    /// `fg1` so hero numbers don't acquire a slight off-white cast against
    /// the deepest `bg0` surface.
    private static func foreground(
        darkAlpha: CGFloat,
        lightAlpha: CGFloat,
        darkIsPureWhite: Bool = false
    ) -> UIColor {
        UIColor { trait in
            if trait.userInterfaceStyle == .light {
                return UIColor(red: 10.0 / 255.0, green: 15.0 / 255.0, blue: 31.0 / 255.0, alpha: lightAlpha)
            }
            if darkIsPureWhite {
                return UIColor(white: 1.0, alpha: darkAlpha)
            }
            return UIColor(red: 235.0 / 255.0, green: 237.0 / 255.0, blue: 245.0 / 255.0, alpha: darkAlpha)
        }
    }

    /// Tint overlay used for `whiteOverlayXX` and `strokeN`. Dark mode lays
    /// `rgba(255,255,255,alpha)`; light mode lays `rgba(10,15,31,alpha)`
    /// (the near-black brand ink) so the same call produces a "darkening"
    /// chip on light and a "brightening" chip on dark.
    private static func overlay(alpha: CGFloat) -> UIColor {
        UIColor { trait in
            if trait.userInterfaceStyle == .light {
                return UIColor(red: 10.0 / 255.0, green: 15.0 / 255.0, blue: 31.0 / 255.0, alpha: alpha)
            }
            return UIColor(white: 1.0, alpha: alpha)
        }
    }
}

/// App-wide spacing constants. The 4px grid (`sp1`...`sp10`) is the underlying
/// design-token (see `tokens.css`); the t-shirt aliases (`xs`...`xxl`) and the
/// semantic aliases (`screenInset`, `cardVerticalPadding`, ...) are kept so
/// existing call sites keep compiling. New code should reach for the `spN`
/// tokens directly so a single design-system bump touches one line.
enum AppSpacing {
    // MARK: - 4px grid (canonical)
    static let sp1: CGFloat = 4
    static let sp2: CGFloat = 8
    static let sp3: CGFloat = 12
    static let sp4: CGFloat = 16
    static let sp5: CGFloat = 20
    static let sp6: CGFloat = 24
    static let sp7: CGFloat = 32
    static let sp8: CGFloat = 40
    static let sp9: CGFloat = 56
    static let sp10: CGFloat = 72

    // MARK: - Legacy t-shirt aliases (pre-token)
    static let xs: CGFloat = sp1   // 4
    static let sm: CGFloat = sp2   // 8
    static let md: CGFloat = sp3   // 12
    static let lg: CGFloat = sp4   // 16
    static let xl: CGFloat = sp6   // 24
    static let xxl: CGFloat = sp7  // 32

    // MARK: - Semantic aliases
    /// Standard horizontal inset for cards / banners against the screen edge.
    static let screenInset: CGFloat = lg
    /// Vertical gap between logical sections (e.g. between the balance card and
    /// the alarms list).
    static let sectionGap: CGFloat = xl
    /// Vertical gap between rows / items inside the same section.
    static let itemGap: CGFloat = md
    /// Horizontal gap between an icon and its inline label.
    static let inlineGap: CGFloat = sm
    /// Vertical padding inside a card (top / bottom).
    static let cardVerticalPadding: CGFloat = md
    /// Horizontal padding inside a card (leading / trailing of card contents).
    static let cardHorizontalPadding: CGFloat = lg
}

/// App-wide corner radius constants — names aligned with `tokens.css`
/// (`--sp-r-xs/sm/md/lg/xl/2xl/pill`). All call sites use the spec naming so
/// a `tokens.css` bump touches one line here.
enum AppRadius {
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12    // matches --sp-r-sm
    static let md: CGFloat = 16    // matches --sp-r-md
    static let lg: CGFloat = 20    // matches --sp-r-lg
    static let xl: CGFloat = 28    // matches --sp-r-xl
    /// "2xl" — Swift identifiers can't start with a digit, hence `r2xl`.
    static let r2xl: CGFloat = 36
    /// Pill / fully-rounded — call sites typically clamp to `bounds.height/2`,
    /// but this constant keeps intent explicit and matches `tokens.css`.
    static let pill: CGFloat = 999
}

/// Typography roles from `tokens.css`. Each role returns a configured `UIFont`
/// resolved via `AppFonts` (currently falls back to system fonts; see
/// `AppFonts` doc comment for the migration plan).
///
/// Mono roles (`moneyXl`/`moneyLg`/`moneyMd`/`moneySm`/`clockXl`/`clockLg`)
/// use JetBrains Mono so digits column-align across rows.
enum AppTypography {

    // MARK: - Display & headings (Manrope)

    /// Hero number / display metric — 88pt heavy.
    static var display: UIFont { AppFonts.sans(.extrabold, 88) }
    /// h1 — 32pt extrabold.
    static var h1: UIFont { AppFonts.sans(.extrabold, 32) }
    /// h2 — 24pt bold.
    static var h2: UIFont { AppFonts.sans(.bold, 24) }
    /// h3 — 20pt bold.
    static var h3: UIFont { AppFonts.sans(.bold, 20) }
    /// h4 — 17pt bold.
    static var h4: UIFont { AppFonts.sans(.bold, 17) }

    // MARK: - Body (Manrope)

    /// Large body — 17pt medium.
    static var bodyLg: UIFont { AppFonts.sans(.medium, 17) }
    /// Body — 15pt medium.
    static var body: UIFont { AppFonts.sans(.medium, 15) }
    /// Meta / secondary — 13pt medium.
    static var meta: UIFont { AppFonts.sans(.medium, 13) }
    /// Caps label — 12pt bold uppercase. Tracking applied per-attributedString
    /// (see `capsKerning`).
    static var caps: UIFont { AppFonts.sans(.bold, 12) }
    /// Letter-spacing for `caps` (matches `+0.12em` in `tokens.css`).
    static let capsKerning: CGFloat = 12 * 0.12

    // MARK: - Buttons (Manrope)

    /// Primary button label — 16pt bold.
    static var button: UIFont { AppFonts.sans(.bold, 16) }
    /// Compact button label — 14pt bold.
    static var buttonSm: UIFont { AppFonts.sans(.bold, 14) }

    // MARK: - Money / numeric (JetBrains Mono)

    /// Hero balance — 56pt mono bold.
    static var moneyXl: UIFont { AppFonts.mono(.bold, 56) }
    /// Section balance — 32pt mono bold.
    static var moneyLg: UIFont { AppFonts.mono(.bold, 32) }
    /// Inline amount — 20pt mono bold.
    static var moneyMd: UIFont { AppFonts.mono(.bold, 20) }
    /// Caption amount / row total — 14pt mono semibold.
    static var moneySm: UIFont { AppFonts.mono(.semibold, 14) }

    // MARK: - Clock (JetBrains Mono)

    /// Alarm-firing clock — 96pt mono ultralight.
    static var clockXl: UIFont { AppFonts.mono(.ultralight, 96) }
    /// Card clock — 64pt mono light.
    static var clockLg: UIFont { AppFonts.mono(.light, 64) }

    // MARK: - Per-role letter-spacing (tokens.css `letter-spacing`)
    //
    // `tokens.css` expresses tracking in em; UIKit's `.kern` attribute wants
    // points, so each constant resolves `em × pointSize` for its role. Apply
    // via `attributedText` (see `kerned(_:font:kerning:)` below) — plain
    // `UILabel.text` ignores tracking.

    /// `display` tracking — −0.025em at 88pt.
    static let displayKerning: CGFloat = kern(em: -0.025, size: 88)
    /// `h1` tracking — −0.01em at 32pt.
    static let h1Kerning: CGFloat = kern(em: -0.01, size: 32)
    /// `h2` tracking — −0.01em at 24pt.
    static let h2Kerning: CGFloat = kern(em: -0.01, size: 24)
    /// `money-xl` tracking — −0.02em at 56pt.
    static let moneyXlKerning: CGFloat = kern(em: -0.02, size: 56)
    /// `clock-xl` tracking — −0.04em at 96pt.
    static let clockXlKerning: CGFloat = kern(em: -0.04, size: 96)
    /// `clock-lg` tracking — −0.04em at 64pt.
    static let clockLgKerning: CGFloat = kern(em: -0.04, size: 64)

    /// Convert an em-based tracking value (as authored in `tokens.css`) to the
    /// point value UIKit's `.kern` attribute expects, for a given font size.
    static func kern(em: CGFloat, size: CGFloat) -> CGFloat {
        em * size
    }

    /// Build an attributed string carrying a typography role's font + tracking.
    /// Call sites assign the result to `UILabel.attributedText`:
    ///
    /// ```swift
    /// label.attributedText = AppTypography.kerned("07:30",
    ///                                             font: AppTypography.clockXl,
    ///                                             kerning: AppTypography.clockXlKerning)
    /// ```
    static func kerned(_ text: String, font: UIFont, kerning: CGFloat) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: font,
            .kern: kerning
        ])
    }

    // MARK: - Legacy section header
    //
    // Pre-token "ВЕРХНИЙ ТЕКСТ" recipe used by SettingsVC / CreateAlarmVC /
    // StatisticsVC. Kept as-is so those screens keep rendering identically
    // until each one migrates onto `caps` in its own UI issue.

    /// Font for table-view section headers. Use `caps` instead in new code.
    static let sectionHeader: UIFont = .preferredFont(forTextStyle: .footnote)
    static let sectionHeaderColor: UIColor = .secondaryLabel
    /// Letter-spacing applied to uppercase headers (matches iOS system grouped
    /// table-view header tracking).
    static let sectionHeaderKerning: CGFloat = 0.5
}

// MARK: - UIColor hex helper

private extension UIColor {
    /// Convenience initializer for `0xRRGGBB` literals so the brand-token
    /// constants above read as in `tokens.css`. Alpha defaults to 1.
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255.0
        let green = CGFloat((hex >> 8) & 0xFF) / 255.0
        let blue = CGFloat(hex & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}
