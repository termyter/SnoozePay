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
    private let iconHost = UIView()
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
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
        iconHost.backgroundColor = AppColors.whiteOverlay08

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
        trailingHost.subviews.forEach { $0.removeFromSuperview() }

        switch status {
        case .granted, .enabled:
            iconHost.backgroundColor = AppColors.money500
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
            iconHost.backgroundColor = AppColors.whiteOverlay08
            iconView.tintColor = AppColors.fg3
            // The 2026-06 mockup renders an *empty* span where this caps
            // label sits — treated as a mockup bug (#238 p.6): the
            // ungranted row keeps its explicit "Дать" affordance.
            mount(capsLabel(text: "Дать", color: AppColors.warn400))
            tapGesture.isEnabled = true
        case .unavailable:
            iconHost.backgroundColor = AppColors.whiteOverlay08
            iconView.tintColor = AppColors.fg3
            mount(capsLabel(text: "Недоступно", color: AppColors.fg3))
            tapGesture.isEnabled = false
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
