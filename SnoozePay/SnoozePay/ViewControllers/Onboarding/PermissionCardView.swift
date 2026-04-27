import UIKit

/// Single permission row mounted inside `PermissionsViewController` (#149).
/// Visually a `.surface` SPCard with a leading SF-Symbol icon, a title +
/// body copy stack, and a trailing affordance (SPButton or SPPill) that the
/// parent VC swaps via `apply(status:)`.
///
/// Kept in its own file so the parent VC stays under SwiftLint's 400-line
/// file-length budget.
enum PermissionKind {
    case notifications
    case criticalAlerts
    case sound

    var iconName: String {
        switch self {
        case .notifications: return "bell.fill"
        case .criticalAlerts: return "exclamationmark.triangle.fill"
        case .sound: return "speaker.wave.2.fill"
        }
    }

    var title: String {
        switch self {
        case .notifications: return "Уведомления"
        case .criticalAlerts: return "Критические оповещения"
        case .sound: return "Звук в беззвучном режиме"
        }
    }

    var body: String {
        switch self {
        case .notifications:
            return "Чтобы будильник звонил даже когда телефон в фоне"
        case .criticalAlerts:
            return "Чтобы будильник звонил даже в режиме «Не беспокоить»"
        case .sound:
            return "Чтобы будильник звонил вслух даже если выключен звук"
        }
    }
}

/// Visual state of a permission card's trailing affordance.
enum PermissionStatus {
    /// Show "Разрешить" SPButton. Tap triggers a real grant.
    case actionable
    /// Show "Разрешено" pill — granted by the user.
    case granted
    /// Show "Включено" pill — auto-configured (no user action needed),
    /// e.g. AVAudioSession `.playback + .duckOthers`.
    case enabled
    /// Show "Недоступно" pill — entitlement / capability missing. The
    /// user can't fix this from the app.
    case unavailable
}

final class PermissionCardView: UIView {

    // MARK: - Public API

    var onPrimaryTap: (() -> Void)?

    // MARK: - Subviews

    private let card = SPCard(tone: .surface)
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    /// Container for the trailing affordance — either an SPButton (actionable)
    /// or an SPPill (granted / enabled / unavailable). We keep a stable host
    /// view and replace its subview on `apply(status:)` so the surrounding
    /// constraints don't churn.
    private let trailingHost = UIView()

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
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: topAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = UIImage(systemName: kind.iconName)?.withRenderingMode(.alwaysTemplate)
        iconView.tintColor = AppColors.money500
        iconView.contentMode = .scaleAspectFit

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = kind.title
        titleLabel.font = AppTypography.h4
        titleLabel.textColor = AppColors.fg1
        titleLabel.numberOfLines = 0

        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        bodyLabel.text = kind.body
        bodyLabel.font = AppTypography.meta
        bodyLabel.textColor = AppColors.fg3
        bodyLabel.numberOfLines = 0

        trailingHost.translatesAutoresizingMaskIntoConstraints = false
        // Ensure the trailing column reserves visual room even before the
        // first `apply(status:)` call lands.
        trailingHost.setContentHuggingPriority(.required, for: .horizontal)
        trailingHost.setContentCompressionResistancePriority(.required, for: .horizontal)

        let copyStack = UIStackView(arrangedSubviews: [titleLabel, bodyLabel])
        copyStack.translatesAutoresizingMaskIntoConstraints = false
        copyStack.axis = .vertical
        copyStack.alignment = .fill
        copyStack.spacing = AppSpacing.sp1

        let cardContent = card.layoutMarginsGuide
        card.addSubview(iconView)
        card.addSubview(copyStack)
        card.addSubview(trailingHost)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: cardContent.leadingAnchor),
            iconView.topAnchor.constraint(equalTo: cardContent.topAnchor, constant: 2),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),

            copyStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: AppSpacing.sp3),
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

    /// Replace the trailing affordance to match the supplied status. Idempotent
    /// — re-application with the same status simply rebuilds the trailing
    /// view (cheap; max 3 swaps over the screen's lifetime).
    func apply(status: PermissionStatus) {
        // Remove the previous trailing view first so multi-call sequences
        // don't stack.
        trailingHost.subviews.forEach { $0.removeFromSuperview() }

        let trailingView: UIView
        switch status {
        case .actionable:
            let button = SPButton(title: "Разрешить", variant: .money, size: .sm)
            button.addTarget(self, action: #selector(primaryTapped), for: .touchUpInside)
            trailingView = button
        case .granted:
            trailingView = SPPill(text: "Разрешено", tone: .money)
        case .enabled:
            trailingView = SPPill(text: "Включено", tone: .money)
        case .unavailable:
            trailingView = SPPill(text: "Недоступно", tone: .neutral)
        }

        trailingView.translatesAutoresizingMaskIntoConstraints = false
        trailingHost.addSubview(trailingView)
        NSLayoutConstraint.activate([
            trailingView.leadingAnchor.constraint(equalTo: trailingHost.leadingAnchor),
            trailingView.trailingAnchor.constraint(equalTo: trailingHost.trailingAnchor),
            trailingView.topAnchor.constraint(equalTo: trailingHost.topAnchor),
            trailingView.bottomAnchor.constraint(equalTo: trailingHost.bottomAnchor)
        ])
    }

    @objc
    private func primaryTapped() {
        onPrimaryTap?()
    }
}
