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

    // MARK: - Public API

    /// Triggered on tap — host wires this to the iOS Settings deeplink.
    var onTap: (() -> Void)?

    func configure(with warning: AlarmBackendWarning) {
        capsLabel.attributedText = NSAttributedString(
            string: warning.title.uppercased(),
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: AppColors.warn300
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

    private let backgroundView: SPGradientView = {
        let colors: [CGColor] = [
            AppColors.warn400.withAlphaComponent(0.14).cgColor,
            AppColors.warn400.withAlphaComponent(0.05).cgColor
        ]
        let view = SPGradientView(colors: colors, locations: [0.0, 1.0])
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = AppRadius.md
        view.layer.masksToBounds = true
        view.layer.borderWidth = 1
        view.layer.borderColor = AppColors.warn400.withAlphaComponent(0.22).cgColor
        view.isUserInteractionEnabled = false
        return view
    }()

    private let iconHost: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = AppColors.warn400.withAlphaComponent(0.18)
        view.layer.cornerRadius = 10
        view.layer.masksToBounds = true
        return view
    }()

    private let iconView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFit
        view.tintColor = AppColors.warn300
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

    /// "Открыть Настройки" — the banner has to lead somewhere, not just state
    /// the problem.
    private let actionLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = AppTypography.buttonSm
        label.textColor = AppColors.warn300
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
                view.refreshBorderColor()
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
        refreshBorderColor()
    }

    private func refreshBorderColor() {
        backgroundView.layer.borderColor = AppColors.warn400.withAlphaComponent(0.22).cgColor
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
