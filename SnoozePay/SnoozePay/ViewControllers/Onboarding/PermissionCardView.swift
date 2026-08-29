import UIKit

/// Single permission row mounted inside `PermissionsViewController` (V2).
///
/// Visual (V2 spec, `docs/design/v2-handoff/components/SPMore2.jsx` lines
/// 39-59): a `.surface` SPCard with 14pt internal spacing — leading 40×40
/// rounded-rect icon (money gradient when granted, `whiteOverlay08` otherwise),
/// title `h4` + subtitle `meta` (`fg3`), trailing checkmark (`money400`) when
/// granted or caps "Дать" (`warn400`) when actionable. Whole card is tappable
/// when actionable, otherwise tap interaction is disabled.
enum PermissionKind {
    case notifications
    case criticalAlerts
    case sound

    var iconName: String {
        switch self {
        case .notifications: return "bell.fill"
        case .criticalAlerts: return "speaker.wave.3.fill"
        case .sound: return "clock.badge.fill"
        }
    }

    var title: String {
        switch self {
        case .notifications: return "Уведомления"
        case .criticalAlerts: return "Critical Alerts"
        case .sound: return "Фоновый режим"
        }
    }

    var body: String {
        switch self {
        case .notifications:
            return "Чтобы показать будильник на экране"
        case .criticalAlerts:
            return "Чтобы звук прошёл через беззвучный режим"
        case .sound:
            return "Чтобы таймеры не убивались системой"
        }
    }
}

/// Visual state of a permission card's trailing affordance.
enum PermissionStatus {
    /// Show "Дать" caps + ungranted icon. Tap triggers a real grant.
    case actionable
    /// Show check glyph + money-tinted icon. User granted.
    case granted
    /// Show check glyph + money-tinted icon — capability is auto-on (e.g.
    /// AVAudioSession config). Behaviourally identical to `.granted`.
    case enabled
    /// Show neutral "—" + ungranted icon — entitlement is missing and the
    /// user can't fix this from the app. Tap is a no-op.
    case unavailable
}

final class PermissionCardView: UIView {

    // MARK: - Public API

    /// Invoked when the whole card is tapped *and* the current status is
    /// `.actionable`. Other statuses ignore the tap (no-ops) so the user
    /// doesn't get a spurious permission prompt.
    var onPrimaryTap: (() -> Void)?

    // MARK: - Subviews

    private let card = SPCard(tone: .surface, padding: 16, cornerRadius: AppRadius.md)
    /// 40×40 tile behind the leading glyph — money gradient for
    /// granted/enabled (#289), flat `whiteOverlay08` otherwise.
    ///
    /// An `SPGradientView`, i.e. the gradient *is* the view's layer, rather
    /// than a `CAGradientLayer` inserted under a plain `UIView` (#553). A
    /// sublayer does not auto-size, and the only place that framed it was this
    /// view's `layoutSubviews` — which runs one level too high: when it fires,
    /// Auto Layout has sized `card` but not yet `card`'s own subviews, so
    /// `iconHost.bounds` was still `.zero` and the layer stayed 0×0 forever.
    /// Measured on a laid-out card: host 40×40, layer 0×0, unhidden, valid
    /// stops, nothing painted — `fgOnMoney` landing on `bg1` at 1.09:1. A
    /// layer that is the view cannot be forgotten.
    ///
    /// Stops start empty on purpose: reading `SPSupport.moneyGradientColors`
    /// in a stored-property initializer bakes whichever theme
    /// `UITraitCollection.current` happened to be into a `CGColor` that never
    /// re-resolves. The same diagnostic measured the *light* ramp
    /// (`#0B7B56 → #096647 → #053D2B`) in both themes. `refreshTileFill()`
    /// owns the stops instead.
    private let iconHost = SPGradientView(colors: [], locations: SPSupport.moneyGradientLocations)
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let trailingHost = UIView()
    private let tapGesture = UITapGestureRecognizer()

    /// Cached so re-applying status can swap the host fill / icon tint
    /// without rebuilding the layout.
    private var currentStatus: PermissionStatus = .actionable

    // MARK: - Init

    init(kind: PermissionKind) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        configure(kind: kind)
        refreshTileFill()
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: PermissionCardView, _) in
                view.refreshTileFill()
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Theme

    @available(iOS, deprecated: 17.0, message: "Replaced by registerForTraitChanges; kept for iOS 15/16.")
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if #available(iOS 17.0, *) { return }
        refreshTileFill()
    }

    // MARK: - Configuration

    private func configure(kind: PermissionKind) {
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)
        configureSubviewProperties(kind: kind)
        let copyStack = UIStackView(arrangedSubviews: [titleLabel, bodyLabel])
        copyStack.translatesAutoresizingMaskIntoConstraints = false
        copyStack.axis = .vertical
        copyStack.alignment = .fill
        copyStack.spacing = 2

        card.addSubview(iconHost)
        iconHost.addSubview(iconView)
        card.addSubview(copyStack)
        card.addSubview(trailingHost)
        activateLayout(copyStack: copyStack)

        tapGesture.addTarget(self, action: #selector(cardTapped))
        addGestureRecognizer(tapGesture)
        isUserInteractionEnabled = true
    }

    private func configureSubviewProperties(kind: PermissionKind) {
        iconHost.translatesAutoresizingMaskIntoConstraints = false
        iconHost.layer.cornerRadius = AppRadius.sm    // 12pt — matches JSX
        iconHost.layer.masksToBounds = true

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = UIImage(systemName: kind.iconName)?
            .withRenderingMode(.alwaysTemplate)
        iconView.tintColor = AppColors.fg3
        iconView.contentMode = .scaleAspectFit

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = kind.title
        titleLabel.font = AppTypography.h4
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 0

        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        bodyLabel.text = kind.body
        bodyLabel.font = AppTypography.meta
        bodyLabel.textColor = AppColors.fg3
        bodyLabel.numberOfLines = 0

        trailingHost.translatesAutoresizingMaskIntoConstraints = false
        trailingHost.setContentHuggingPriority(.required, for: .horizontal)
        trailingHost.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    private func activateLayout(copyStack: UIStackView) {
        let cardContent = card.layoutMarginsGuide
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: topAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),

            iconHost.leadingAnchor.constraint(equalTo: cardContent.leadingAnchor),
            iconHost.centerYAnchor.constraint(equalTo: cardContent.centerYAnchor),
            iconHost.widthAnchor.constraint(equalToConstant: 40),
            iconHost.heightAnchor.constraint(equalToConstant: 40),

            iconView.centerXAnchor.constraint(equalTo: iconHost.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconHost.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),

            copyStack.leadingAnchor.constraint(equalTo: iconHost.trailingAnchor, constant: 14),
            copyStack.topAnchor.constraint(equalTo: cardContent.topAnchor),
            copyStack.bottomAnchor.constraint(equalTo: cardContent.bottomAnchor),
            copyStack.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingHost.leadingAnchor,
                constant: -AppSpacing.sp3
            ),

            trailingHost.trailingAnchor.constraint(equalTo: cardContent.trailingAnchor),
            trailingHost.centerYAnchor.constraint(equalTo: cardContent.centerYAnchor)
        ])
    }

    // MARK: - Status rendering

    /// Replace the trailing affordance + icon fill to match the supplied
    /// status. Idempotent — re-application with the same status simply
    /// rebuilds the trailing view (cheap; max a handful of swaps over the
    /// screen's lifetime).
    func apply(status: PermissionStatus) {
        currentStatus = status
        refreshTileFill()
        trailingHost.subviews.forEach { $0.removeFromSuperview() }

        switch status {
        case .granted, .enabled:
            iconView.tintColor = AppColors.fgOnMoney
            let configuration = UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)
            let imageView = UIImageView(
                image: UIImage(systemName: "checkmark", withConfiguration: configuration)?
                    .withRenderingMode(.alwaysTemplate)
            )
            imageView.tintColor = AppColors.money400
            imageView.contentMode = .scaleAspectFit
            mount(imageView)
            tapGesture.isEnabled = false
        case .actionable:
            iconView.tintColor = AppColors.fg3
            // The 2026-06 mockup renders an *empty* span where this caps
            // label sits — treated as a mockup bug (#238 p.6): the
            // ungranted row keeps its explicit "Дать" affordance.
            mount(capsLabel(text: "Дать", color: AppColors.warn400))
            tapGesture.isEnabled = true
        case .unavailable:
            iconView.tintColor = AppColors.fg3
            mount(capsLabel(text: "Недоступно", color: AppColors.fg3))
            tapGesture.isEnabled = false
        }
    }

    /// Re-resolve the tile fill for the current status *and* the current
    /// traits.
    ///
    /// Takes the trait-explicit `moneyGradientColors(for:)` rather than the
    /// `UITraitCollection.current`-reading computed property: these stops land
    /// in `CAGradientLayer.colors` as plain `CGColor`, which never re-resolves
    /// on a theme flip. Same contract as
    /// `StreakModalViewController.refreshLayerColors()`. The ungranted states
    /// clear the stops entirely so the flat `whiteOverlay08` background — a
    /// dynamic `UIColor`, which UIKit does re-resolve — is what shows through.
    private func refreshTileFill() {
        switch currentStatus {
        case .granted, .enabled:
            iconHost.backgroundColor = .clear
            iconHost.refresh(
                colors: SPSupport.moneyGradientColors(for: traitCollection),
                locations: SPSupport.moneyGradientLocations
            )
        case .actionable, .unavailable:
            iconHost.backgroundColor = AppColors.whiteOverlay08
            iconHost.refresh(colors: [], locations: SPSupport.moneyGradientLocations)
        }
    }

    // MARK: - Helpers

    private func capsLabel(text: String, color: UIColor) -> UILabel {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.attributedText = NSAttributedString(
            string: text.uppercased(),
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: color
            ]
        )
        return label
    }

    private func mount(_ view: UIView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        trailingHost.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: trailingHost.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingHost.trailingAnchor),
            view.topAnchor.constraint(equalTo: trailingHost.topAnchor),
            view.bottomAnchor.constraint(equalTo: trailingHost.bottomAnchor)
        ])
    }

    @objc
    private func cardTapped() {
        guard currentStatus == .actionable else { return }
        onPrimaryTap?()
    }
}
