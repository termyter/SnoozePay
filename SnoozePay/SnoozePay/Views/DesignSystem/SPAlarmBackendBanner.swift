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
    // The light emphasis used to be `fgOnWarn`, which worked only while that
    // token was near-black ink. Once the accent scales became theme-aware
    // (#489) `fgOnWarn` inverted to white — correct for its actual job, text
    // on a SOLID warn fill, but wrong here: the banner's fill is `warn400` at
    // 5–14% alpha, i.e. barely tinted background. White on it measures
    // 1.15:1. The token was being used for the wrong surface, and the light
    // emphasis now takes a dark warn TONE instead of on-fill ink.
    //
    // Measured contrasts of the values below (sRGB, WCAG 2.1):
    //   dark  — warn300 on fill rgb(41,34,26)     = 11.17:1 / 13.31:1
    //   light — warn600 on fill rgb(231,225,217)  =  7.14:1 /  8.06:1
    //   light — fgOnWarn on the solid warn500 icon tile = 6.98:1
    // `warn500` also clears the floor (5.38:1) but `warn600` keeps the
    // headroom the dark side has — this is the one banner whose entire job is
    // to be unmissable.

    /// Caps title + CTA colour. Internal (not private) so
    /// `SPAlarmBackendBannerContrastTests` can MEASURE the ratio instead of
    /// trusting a comment.
    static let emphasisColor = UIColor { trait in
        trait.userInterfaceStyle == .dark ? AppColors.warn300 : AppColors.warn600
    }

    /// Icon tile fill — a faint warn wash on dark, a solid warn chip on light
    /// (a 18%-alpha wash over a pale background carries no signal at all).
    static let iconTileColor = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? AppColors.warn400.withAlphaComponent(0.18)
            : AppColors.warn500
    }

    /// Icon glyph — reads against whichever tile it sits on.
    static let iconColor = UIColor { trait in
        trait.userInterfaceStyle == .dark ? AppColors.warn300 : AppColors.fgOnWarn
    }

    /// Border — decorative, but the light variant needs real saturation to
    /// separate the card from `bg0`.
    static var borderColor: UIColor {
        UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? AppColors.warn400.withAlphaComponent(0.22)
                : AppColors.warn500.withAlphaComponent(0.45)
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

    private let backgroundView: SPGradientView = {
        let colors: [CGColor] = [
            AppColors.warn400.withAlphaComponent(SPAlarmBackendBanner.fillAlphas[0]).cgColor,
            AppColors.warn400.withAlphaComponent(SPAlarmBackendBanner.fillAlphas[1]).cgColor
        ]
        let view = SPGradientView(colors: colors, locations: [0.0, 1.0])
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = AppRadius.md
        view.layer.masksToBounds = true
        view.layer.borderWidth = 1
        view.layer.borderColor = SPAlarmBackendBanner.borderColor.cgColor
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

    /// "Разрешить" / "Открыть Настройки" — the banner has to lead somewhere,
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
    /// a light/dark flip has to re-resolve them by hand.
    private func refreshDynamicColors() {
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
