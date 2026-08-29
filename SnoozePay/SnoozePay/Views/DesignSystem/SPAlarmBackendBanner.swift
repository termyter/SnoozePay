import UIKit

/// Warn-tinted disabled-state banner for the alarms list (#428).
///
/// ```
///  ┌─────────────────────────────────────────────────┐
///  │  [!]  БУДИЛЬНИКИ НЕ ЗАЗВОНЯТ                 ›  │
///  │       Разрешение на будильники и уведомления…   │
///  │       Открыть Настройки                         │
///  └─────────────────────────────────────────────────┘
/// ```
///
/// Same recipe as `AlarmsStreakBannerView` (14×16 padding, 16pt radius,
/// tinted glass fill + 1pt border, 36×36 gradient icon tile, caps title, meta
/// body, chevron, whole-surface tap target) with the money palette swapped for
/// `warn` — so the two banners read as one family while the alarms-are-broken
/// state is unmistakably the louder of the pair.
///
/// Unlike the streak banner this one is NOT a `tableHeaderView`: it must stay
/// visible when the user has no alarms yet (the table is hidden behind the
/// empty state exactly then), so the host pins it between the sticky header
/// and the table.
final class SPAlarmBackendBanner: UIView {

    // MARK: - Theme-aware palette
    //
    // The original bug (#428 review): the banner painted its title with
    // `warn300` in both themes. `bg0` in light mode is `#F4F6FB`, so the
    // composited fill lands on a near-white wash and the amber measured
    // **1.21:1** on it. The alarms list doesn't force `.dark`, so on a light
    // system theme the title and the CTA of the one banner whose entire job
    // is to be unmissable were effectively invisible.
    //
    // `warn300` is theme-aware since #489, but that did not retire the
    // problem: its light value (`#BE7B09`) still only reaches 2.68:1 on the
    // dense end of the fill, so it remains unusable here and
    // `testWarn300_isBelowTheFloorOnLightFill` keeps measuring it.
    //
    // The light emphasis used to be `fgOnWarn`, and that is still wrong here
    // whichever value the token carries: the banner's fill is `warn400` at
    // 5–14% alpha, i.e. barely tinted background, and on-fill ink is solved
    // for a SOLID fill. The light emphasis takes a dark warn TONE instead.
    //
    // Measured contrasts of the values below (sRGB, WCAG 2.1):
    //   dark  — warn300 on fill rgb(41,34,26)     = 11.17:1 / 13.31:1
    //   light — warn600 on fill rgb(231,225,217)  =  7.14:1 /  8.06:1
    //   both  — fgOnWarn on the solid `warnFill500` icon tile = 8.79:1
    // The last line moved twice. #520 replaced the bronze ink tone under white
    // ink (6.98:1) with the canon amber under `#1A0F00` in LIGHT; #580 gave
    // dark the same tile, so it is no longer a per-theme number.
    // `warn500` also clears the floor as emphasis (5.38:1) but `warn600` keeps
    // the headroom the dark side has — this is the one banner whose entire job
    // is to be unmissable.

    /// Caps title + CTA colour. Internal (not private) so
    /// `SPAlarmBackendBannerContrastTests` can MEASURE the ratio instead of
    /// trusting a comment.
    static let emphasisColor = UIColor { trait in
        trait.userInterfaceStyle == .dark ? AppColors.warn300 : AppColors.warn600
    }

    /// Icon tile fill — a SOLID warn chip in both themes (#580).
    ///
    /// This used to be the one deliberate asymmetry in the file: light took the
    /// solid `warnFill500` because an 18%-alpha wash over a pale page carries
    /// no signal at all, dark kept `warn400@18%`. The dark half was the same
    /// composite defect #580 measured on the price chip — the tile landed on
    /// `#4F3D23`, a brown 1.52:1 away from the banner's own wash, so the one
    /// element meant to shout was a slightly warmer rectangle.
    ///
    /// Recomputed for the pair below (glyph on tile / tile against the dense
    /// stop of the banner fill it sits on):
    ///
    ///     dark  was  warn300 on #4F3D23  7.40:1  ·  tile vs fill 1.52:1
    ///     dark  now  fgOnWarn on #F59E0B 8.79:1  ·  tile vs fill 7.34:1
    ///     light was/now  fgOnWarn on #F59E0B 8.79:1 · tile vs fill 1.65:1
    ///
    /// Light's 1.65:1 is amber's ceiling against a near-white page and did not
    /// move; what marks the tile out there is the near-black glyph on it, which
    /// is exactly why `fgOnWarn` exists. Both numbers are pinned by
    /// `SPAlarmBackendBannerContrastTests`.
    ///
    /// The tile is theme-flat now, so it is also out of the `CGColor`-baking
    /// class — there is nothing left for a theme flip to re-resolve here.
    static let iconTileColor = AppColors.warnFill500

    /// Icon glyph — ink for the solid tile above, in both themes.
    static let iconColor = AppColors.fgOnWarn

    // MARK: - The edge (#538)
    //
    // Measured against the page the banner sits on (`bg0`, set by
    // `AlarmsListViewController`), sRGB / WCAG 2.1, BEFORE this change:
    //
    //     dense fill  warn400@14%              dark 1.26:1   light 1.20:1
    //     sparse fill warn400@5%               dark 1.06:1   light 1.07:1
    //     border      warn400@22% / warn500@45%
    //                                          dark 1.55:1   light 2.06:1
    //
    // So the banner had no edge in either theme — the same half of the defect
    // `AlarmsStreakBannerView` carried until #531. It matters more here: this
    // is the one banner that exists only in a broken state, to say the alarms
    // will not ring. A warning that melts into the page is not doing its job,
    // and the two banners are supposed to read as one family.
    //
    // **The fill stays a decorative wash.** Not taste, arithmetic: pushing
    // `warn400` to the alpha that would reach 3:1 against the page costs the
    // ink sitting on it. 45% on dark drops the title from 11.22:1 to 4.68:1;
    // 74% on light drops `warn600` to 2.83:1 — under the 4.5:1 floor this
    // whole file exists to defend. A denser surface buys a container and
    // sells the text. Stepping the surface "one darker" is not on the table
    // either: the entire `bg0`…`bg4` ramp measures 1.07–1.61:1 against the
    // page in both themes (#518).
    //
    // **So the border carries the edge alone, and has to earn it.** Alphas
    // raised to the pair below — the same pair `AlarmsStreakBannerView` took
    // in #531 (0.50 / 0.75), so the family keeps one recipe. The TONES are
    // unchanged: dark stays `warn400`, light stays `warn500`, because the
    // light bronze is the saturated end of the scale and gives the louder
    // banner its headroom. #520 split warn into ink and fill and this border
    // stayed on the INK half on purpose — as `warnFill500` the same 75% stroke
    // measures 1.69:1 against the page instead of 3.71:1, i.e. it would give
    // back exactly the edge #538 was opened to buy.
    //
    //     border      warn400@50% / warn500@75%
    //                                          dark 3.50:1   light 3.72:1
    //
    // That is border-over-page, the conservative reading. The 1pt stroke
    // actually composites over the wash, measuring 4.25:1 dark / 3.98:1 light
    // against the page and 3.37:1 / 3.31:1 against the wash on its inner
    // side, so both sides of the line clear 3:1.
    // `SPAlarmBackendBannerContrastTests` pins all of the numbers above.

    /// Border alpha per theme. Internal so the contrast test measures the SAME
    /// alphas the view renders instead of a copy of them.
    static let borderAlphas: (dark: CGFloat, light: CGFloat) = (0.50, 0.75)

    /// Border — decorative in origin, load-bearing in fact: it is the only
    /// thing separating this banner from the page, in either theme.
    static var borderColor: UIColor {
        UIColor { trait in
            let tone = trait.userInterfaceStyle == .dark ? AppColors.warn400 : AppColors.warn500
            let alpha = trait.userInterfaceStyle == .dark ? Self.borderAlphas.dark : Self.borderAlphas.light
            return tone.resolvedColor(with: trait).withAlphaComponent(alpha)
        }
    }

    // MARK: - Public API

    /// Triggered on tap — host wires this to the iOS Settings deeplink.
    var onTap: (() -> Void)?

    /// Last rendered copy — kept so a theme flip can re-resolve the caps
    /// title's snapshotted colour without the host re-configuring.
    private var warning: AlarmBackendWarning?

    func configure(with warning: AlarmBackendWarning) {
        self.warning = warning
        capsLabel.attributedText = NSAttributedString(
            string: warning.title.uppercased(),
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                // `attributedText` snapshots the resolved colour, so re-resolve
                // against the live traits (the label's `textColor` path can't
                // carry it) — `refreshDynamicColors` re-runs this on a theme flip.
                .foregroundColor: Self.emphasisColor.resolvedColor(with: traitCollection)
            ]
        )
        metaLabel.text = warning.message
        actionLabel.text = warning.actionTitle
        // One VoiceOver element for the whole banner (mirrors SPButton): the
        // title and the reason are read together, then the action.
        accessibilityLabel = "\(warning.title). \(warning.message)"
        accessibilityHint = warning.actionTitle
    }

    // MARK: - Subviews

    /// Fill alphas of the two-stop tint, densest stop first. Internal so the
    /// contrast test composites the SAME values the view renders.
    static let fillAlphas: [CGFloat] = [0.14, 0.05]
    static let fillLocations: [NSNumber] = [0.0, 1.0]

    /// Fill stops resolved against `trait`. Trait-explicit on purpose: the
    /// plain `.cgColor` path snapshots `UITraitCollection.current`, which is
    /// not necessarily this view's traits — and a `CGColor` has no link back
    /// to the token it came from, so it never re-resolves afterwards. That is
    /// the freeze `AlarmsStreakBannerView` had in #531; this file had the same
    /// one, hidden because `refreshDynamicColors()` repainted the border and
    /// the caps title but never the ramp.
    static func fillColors(for trait: UITraitCollection) -> [CGColor] {
        let warn = AppColors.warn400.resolvedColor(with: trait)
        return fillAlphas.map { warn.withAlphaComponent($0).cgColor }
    }

    /// Warn-tinted glass. Stops start empty on purpose — see `fillColors`;
    /// `refreshDynamicColors()` owns them, and `init` runs it once.
    private let backgroundView: SPGradientView = {
        let view = SPGradientView(colors: [], locations: SPAlarmBackendBanner.fillLocations)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = AppRadius.md
        view.layer.masksToBounds = true
        view.layer.borderWidth = 1
        view.isUserInteractionEnabled = false
        return view
    }()

    private let iconHost: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = SPAlarmBackendBanner.iconTileColor
        view.layer.cornerRadius = 10
        view.layer.masksToBounds = true
        return view
    }()

    private let iconView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFit
        view.tintColor = SPAlarmBackendBanner.iconColor
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)
        view.image = UIImage(systemName: "exclamationmark.triangle.fill", withConfiguration: config)
        return view
    }()

    private let capsLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.8
        return label
    }()

    private let metaLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = AppTypography.meta
        label.textColor = AppColors.fg2
        label.numberOfLines = 0
        return label
    }()

    /// «Разрешить» / «Открыть Настройки» — the banner has to lead somewhere,
    /// not just state the problem. Which one it is comes from the warning.
    private let actionLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = AppTypography.buttonSm
        label.textColor = SPAlarmBackendBanner.emphasisColor
        label.numberOfLines = 1
        return label
    }()

    private let chevronView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFit
        view.tintColor = AppColors.fg3
        let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        view.image = UIImage(systemName: "chevron.right", withConfiguration: config)
        return view
    }()

    private let tapButton: UIControl = {
        let view = UIControl()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        return view
    }()

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureLayout()
        refreshDynamicColors()
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: SPAlarmBackendBanner, _) in
                view.refreshDynamicColors()
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @available(iOS, deprecated: 17.0, message: "Replaced by registerForTraitChanges; kept for iOS 15/16.")
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if #available(iOS 17.0, *) { return }
        refreshDynamicColors()
    }

    /// `CGColor` and `NSAttributedString` both snapshot the resolved colour, so
    /// a light/dark flip has to re-resolve them by hand. The FILL is named
    /// first deliberately: it was missing here until #538, so the ramp kept
    /// whatever theme was current when the banner was built while the ink
    /// above it re-resolved.
    private func refreshDynamicColors() {
        backgroundView.refresh(
            colors: Self.fillColors(for: traitCollection),
            locations: Self.fillLocations
        )
        backgroundView.layer.borderColor = Self.borderColor.resolvedColor(with: traitCollection).cgColor
        if let warning {
            configure(with: warning)
        }
    }

    // MARK: - Layout

    private func configureLayout() {
        backgroundColor = .clear
        isAccessibilityElement = true
        accessibilityTraits = .button

        addSubview(backgroundView)
        addSubview(iconHost)
        iconHost.addSubview(iconView)
        addSubview(capsLabel)
        addSubview(metaLabel)
        addSubview(actionLabel)
        addSubview(chevronView)
        addSubview(tapButton)

        tapButton.addTarget(self, action: #selector(handleTap), for: .touchUpInside)

        let inset = AppSpacing.screenInset

        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -AppSpacing.sp3),

            iconHost.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 16),
            iconHost.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 14),
            iconHost.widthAnchor.constraint(equalToConstant: 36),
            iconHost.heightAnchor.constraint(equalToConstant: 36),

            iconView.centerXAnchor.constraint(equalTo: iconHost.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconHost.centerYAnchor),

            capsLabel.leadingAnchor.constraint(equalTo: iconHost.trailingAnchor, constant: AppSpacing.sp3),
            capsLabel.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 14),
            capsLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: chevronView.leadingAnchor,
                constant: -AppSpacing.sp2
            ),

            metaLabel.leadingAnchor.constraint(equalTo: capsLabel.leadingAnchor),
            metaLabel.topAnchor.constraint(equalTo: capsLabel.bottomAnchor, constant: 4),
            metaLabel.trailingAnchor.constraint(
                equalTo: chevronView.leadingAnchor,
                constant: -AppSpacing.sp2
            ),

            actionLabel.leadingAnchor.constraint(equalTo: capsLabel.leadingAnchor),
            actionLabel.topAnchor.constraint(equalTo: metaLabel.bottomAnchor, constant: AppSpacing.sp2),
            actionLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: chevronView.leadingAnchor,
                constant: -AppSpacing.sp2
            ),
            actionLabel.bottomAnchor.constraint(
                equalTo: backgroundView.bottomAnchor,
                constant: -14
            ),

            chevronView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -16),
            chevronView.centerYAnchor.constraint(equalTo: backgroundView.centerYAnchor),
            chevronView.widthAnchor.constraint(equalToConstant: 14),
            chevronView.heightAnchor.constraint(equalToConstant: 14),

            tapButton.topAnchor.constraint(equalTo: backgroundView.topAnchor),
            tapButton.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
            tapButton.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
            tapButton.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor)
        ])
    }

    @objc private func handleTap() {
        SPSupport.animatePress(backgroundView, pressed: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + SPSupport.durationQuick) { [weak self] in
            guard let self else { return }
            SPSupport.animatePress(self.backgroundView, pressed: false)
        }
        onTap?()
    }
}
