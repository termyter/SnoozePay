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
/// - Border: 1pt `money400@18%`.
/// - 36×36 rounded-rect money gradient with flame icon (`fgOnMoney`).
/// - Caps title `money300`, meta `fg2`, chevron `fg3`.
///
/// Hosted as `tableHeaderView` of the alarms list so it scrolls with the
/// cards (per spec: "First card (when streak > 0): Streak summary banner —
/// then alarm cards via UITableView").
final class AlarmsStreakBannerView: UIView {

    // MARK: - Public API

    /// Triggered on tap — host wires this to open `StreakModalViewController`.
    var onTap: (() -> Void)?

    /// Configure with current streak + savings. Pass `streakDays = 0` to
    /// render no copy (the host should hide the view instead).
    func configure(streakDays: Int, savedAmount: Decimal) {
        let title = "\(streakDays) \(Self.daysWord(for: streakDays)) БЕЗ ОТКЛАДЫВАНИЙ"
        capsLabel.attributedText = NSAttributedString(
            string: title.uppercased(),
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: AppColors.money300
            ]
        )
        let formatted = NSDecimalNumber(decimal: savedAmount).decimalValue.formattedRubles()
        metaLabel.text = "Сэкономили \(formatted)"
    }

    // MARK: - Subviews

    private let backgroundView: SPGradientView = {
        // Money-tinted glass — two-stop 135° from money400@12% → money400@4%.
        let colors: [CGColor] = [
            AppColors.money400.withAlphaComponent(0.12).cgColor,
            AppColors.money400.withAlphaComponent(0.04).cgColor
        ]
        let view = SPGradientView(colors: colors, locations: [0.0, 1.0])
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = AppRadius.md
        view.layer.masksToBounds = true
        view.layer.borderWidth = 1
        view.layer.borderColor = AppColors.money400.withAlphaComponent(0.18).cgColor
        view.isUserInteractionEnabled = false
        return view
    }()

    /// 36×36 money-gradient rounded square with flame icon.
    private let iconHost: SPGradientView = {
        let view = SPGradientView(
            colors: SPSupport.moneyGradientColors,
            locations: SPSupport.moneyGradientLocations
        )
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
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: AlarmsStreakBannerView, _) in
                view.backgroundView.layer.borderColor = AppColors.money400.withAlphaComponent(0.18).cgColor
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
        backgroundView.layer.borderColor = AppColors.money400.withAlphaComponent(0.18).cgColor
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
