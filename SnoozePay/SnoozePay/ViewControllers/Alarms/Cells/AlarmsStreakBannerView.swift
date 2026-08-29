import UIKit

/// Streak summary banner that scrolls above the alarm cards.
///
/// Reference: `docs/design/v2-handoff/components/SPScreensV2.jsx` L337-355.
///
/// Visual recipe — money-tinted glass:
/// ```
///  ┌─────────────────────────────────────────────────┐
///  │  [🔥]  5 ДНЕЙ БЕЗ ОТКЛАДЫВАНИЙ              ›  │
///  │        Сэкономили 250 ₽                         │
///  └─────────────────────────────────────────────────┘
/// ```
///
/// - 14×16 padding, 16pt radius.
/// - Background: `linear-gradient(135deg, money400@12% 0%, money400@4% 100%)`.
/// - Border: 1pt `money400`, alpha per theme (see `borderColor(for:)`).
/// - 36×36 rounded-rect money gradient with flame icon (`fgOnMoney`).
/// - Caps title `money300`, meta `fg2`, chevron `fg3`.
///
/// Hosted as `tableHeaderView` of the alarms list so it scrolls with the
/// cards (per spec: "First card (when streak > 0): Streak summary banner —
/// then alarm cards via UITableView").
final class AlarmsStreakBannerView: UIView {

    // MARK: - Theme-aware surface
    //
    // Two things were wrong here (#531).
    //
    // **The fill froze.** Every stop was taken as `.cgColor` off a dynamic
    // token inside a property initializer and handed to `CAGradientLayer`.
    // A `CGColor` has no link back to the `UIColor` it was resolved from, so
    // the ramp stayed on whichever theme was current at `init` while the ink
    // above it re-resolved. `registerForTraitChanges` was present but
    // repainted only `borderColor` — half the state, which is exactly why the
    // file read as correct. Sixth instance of this class: #491, #494, #498,
    // #507, #516.
    //
    // **The surface was not a surface.** Measured against the page the banner
    // sits on (`bg0`, `AlarmsListViewController`), sRGB / WCAG 2.1:
    //
    //     dense fill  money400@12%   dark 1.20:1   light 1.17:1
    //     sparse fill money400@4%    dark 1.05:1   light 1.05:1
    //     border      money400@18%   dark 1.38:1   light 1.28:1
    //
    // So neither the fill NOR the border separated the banner from the page —
    // at 1.28:1 a 1pt line is not an edge, it is a rumour. Taking the surface
    // "one step darker" is not available either: the whole `bg0…bg4` ramp
    // measures 1.07–1.61:1 against the page in both themes (#518).
    //
    // **The decision.** The tint stays a decorative wash — that is the canon
    // recipe and the banner is identified by its caps title, icon tile and
    // chevron, not by its container, so WCAG 1.4.11 is not in play. The edge
    // is carried by the border ALONE, and therefore the border has to earn
    // it: raised to the alphas below, which clear the 3:1 non-text floor
    // against the page in both themes. Border over the page is the
    // conservative reading — the layer stroke actually composites over the
    // wash, which measures 3.20–4.02:1.

    /// Fill alphas of the money-tinted glass, densest stop first. Internal so
    /// `AlarmsStreakBannerThemeTests` composites the SAME values the view
    /// renders instead of a copy of them.
    static let fillAlphas: [CGFloat] = [0.12, 0.04]
    static let fillLocations: [NSNumber] = [0.0, 1.0]

    /// Border alpha per theme. Dark 3.40:1 and light 3.15:1 against `bg0` —
    /// see the block above for why these are not the canon 18%.
    static let borderAlphas: (dark: CGFloat, light: CGFloat) = (0.50, 0.75)

    /// Fill stops resolved against `trait`. Trait-explicit on purpose: the
    /// plain `.cgColor` path snapshots `UITraitCollection.current`, which
    /// inside a view method is not necessarily this view's traits.
    static func fillColors(for trait: UITraitCollection) -> [CGColor] {
        let money = AppColors.money400.resolvedColor(with: trait)
        return fillAlphas.map { money.withAlphaComponent($0).cgColor }
    }

    /// The banner's only edge — see the decision recorded above.
    static func borderColor(for trait: UITraitCollection) -> UIColor {
        let alpha = trait.userInterfaceStyle == .dark ? borderAlphas.dark : borderAlphas.light
        return AppColors.money400.resolvedColor(with: trait).withAlphaComponent(alpha)
    }

    // MARK: - Rendered state (for tests)
    //
    // Read-only windows onto what the layers actually carry, so a test can
    // assert the rendered stops rather than re-deriving them.

    var renderedFillStops: [CGColor] { stops(of: backgroundView) }
    var renderedIconStops: [CGColor] { stops(of: iconHost) }
    var renderedBorderColor: CGColor? { backgroundView.layer.borderColor }

    private func stops(of view: SPGradientView) -> [CGColor] {
        guard let layer = view.layer as? CAGradientLayer else { return [] }
        return (layer.colors as? [CGColor]) ?? []
    }

    // MARK: - Public API

    /// Triggered on tap — host wires this to open `StreakModalViewController`.
    var onTap: (() -> Void)?

    /// Last rendered copy — kept so a theme flip can re-resolve the caps
    /// title's snapshotted colour without the host re-configuring.
    private var lastCopy: (streakDays: Int, savedAmount: Decimal)?

    /// Configure with current streak + savings. Pass `streakDays = 0` to
    /// render no copy (the host should hide the view instead).
    func configure(streakDays: Int, savedAmount: Decimal) {
        lastCopy = (streakDays, savedAmount)
        let title = "\(streakDays) \(Self.daysWord(for: streakDays)) БЕЗ ОТКЛАДЫВАНИЙ"
        capsLabel.attributedText = NSAttributedString(
            string: title.uppercased(),
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                // `attributedText` snapshots the resolved colour the same way
                // `CGColor` does, so it has to be resolved against the live
                // traits and re-run on a flip (mirrors SPAlarmBackendBanner).
                .foregroundColor: AppColors.money300.resolvedColor(with: traitCollection)
            ]
        )
        let formatted = NSDecimalNumber(decimal: savedAmount).decimalValue.formattedRubles()
        metaLabel.text = "Сэкономили \(formatted)"
    }

    // MARK: - Subviews

    /// Money-tinted glass. Stops start empty on purpose — resolving a dynamic
    /// token inside a property initializer reads `UITraitCollection.current`,
    /// not this view's traits. `refreshDynamicColors()` owns them.
    private let backgroundView: SPGradientView = {
        let view = SPGradientView(colors: [], locations: AlarmsStreakBannerView.fillLocations)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = AppRadius.md
        view.layer.masksToBounds = true
        view.layer.borderWidth = 1
        view.isUserInteractionEnabled = false
        return view
    }()

    /// 36×36 money-gradient rounded square with flame icon. Same empty-stops
    /// contract as `backgroundView`.
    private let iconHost: SPGradientView = {
        let view = SPGradientView(colors: [], locations: SPSupport.moneyGradientLocations)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 10
        view.layer.masksToBounds = true
        return view
    }()

    private let iconView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFit
        view.tintColor = AppColors.fgOnMoney
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)
        view.image = UIImage(systemName: "flame.fill", withConfiguration: config)
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
        configure()
        refreshDynamicColors()
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: AlarmsStreakBannerView, _) in
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

    /// `CGColor` and `NSAttributedString` both snapshot the resolved colour,
    /// so a light/dark flip has to re-resolve every one of them by hand.
    private func refreshDynamicColors() {
        backgroundView.refresh(
            colors: Self.fillColors(for: traitCollection),
            locations: Self.fillLocations
        )
        backgroundView.layer.borderColor = Self.borderColor(for: traitCollection).cgColor
        iconHost.refresh(
            colors: SPSupport.moneyGradientColors(for: traitCollection),
            locations: SPSupport.moneyGradientLocations
        )
        if let lastCopy {
            configure(streakDays: lastCopy.streakDays, savedAmount: lastCopy.savedAmount)
        }
    }

    // MARK: - Layout

    private func configure() {
        backgroundColor = .clear

        addSubview(backgroundView)
        addSubview(iconHost)
        iconHost.addSubview(iconView)
        addSubview(capsLabel)
        addSubview(metaLabel)
        addSubview(chevronView)
        addSubview(tapButton)

        tapButton.addTarget(self, action: #selector(handleTap), for: .touchUpInside)

        let inset = AppSpacing.screenInset

        NSLayoutConstraint.activate([
            // Banner background — pinned full-width inside the screen inset.
            backgroundView.topAnchor.constraint(equalTo: topAnchor, constant: 0),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -AppSpacing.sp3),

            // Flame icon — 36×36 leading.
            iconHost.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 16),
            iconHost.centerYAnchor.constraint(equalTo: backgroundView.centerYAnchor),
            iconHost.widthAnchor.constraint(equalToConstant: 36),
            iconHost.heightAnchor.constraint(equalToConstant: 36),

            iconView.centerXAnchor.constraint(equalTo: iconHost.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconHost.centerYAnchor),

            // Caps + meta — vertical text column to the right of the icon.
            capsLabel.leadingAnchor.constraint(equalTo: iconHost.trailingAnchor, constant: AppSpacing.sp3),
            capsLabel.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 14),
            capsLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: chevronView.leadingAnchor,
                constant: -AppSpacing.sp2
            ),

            metaLabel.leadingAnchor.constraint(equalTo: capsLabel.leadingAnchor),
            metaLabel.topAnchor.constraint(equalTo: capsLabel.bottomAnchor, constant: 4),
            metaLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: chevronView.leadingAnchor,
                constant: -AppSpacing.sp2
            ),
            metaLabel.bottomAnchor.constraint(
                lessThanOrEqualTo: backgroundView.bottomAnchor,
                constant: -14
            ),

            // Chevron right edge.
            chevronView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -16),
            chevronView.centerYAnchor.constraint(equalTo: backgroundView.centerYAnchor),
            chevronView.widthAnchor.constraint(equalToConstant: 14),
            chevronView.heightAnchor.constraint(equalToConstant: 14),

            // Full-banner tap target sits on top of everything so the whole
            // surface is hittable (matches `<button>` in the JSX spec).
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

    // MARK: - Pluralisation

    /// Russian plural for "день" — `1 день / 2-4 дня / 5+ дней`.
    private static func daysWord(for count: Int) -> String {
        let abs = Swift.abs(count)
        let mod10 = abs % 10
        let mod100 = abs % 100
        if mod10 == 1 && mod100 != 11 { return "день" }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return "дня" }
        return "дней"
    }
}
