import UIKit
import UserNotifications

/// Permissions screen — V3 (`docs/design/v2-handoff/components/SPMore2.jsx`
/// `Permissions`, artboard 05). Shown once after Onboarding finishes, before
/// the main alarms list. Caps "последний шаг" eyebrow → h1 "Чтобы будильник
/// работал" → body copy → two permission cards (Notifications, Background)
/// → "Готово" CTA in flow 28pt after the cards (not pinned to the bottom).
/// Layout padding follows the JSX `70px 16px 52px` frame: 16pt below the
/// safe-area top, 16pt sides.
///
/// The JSX draws a third card, "Critical Alerts", which #566 removed: the
/// only thing it promised — ringing through silent mode and Do Not Disturb —
/// is already delivered by AlarmKit, the current scheduling backend, while
/// the `com.apple.developer.usernotifications.critical-alerts` entitlement
/// is granted by Apple on application and effectively never to alarm apps.
/// The card therefore sat permanently on "Недоступно". Card spacing is
/// unchanged (`AppSpacing.sp3`, the JSX `gap: 12`); the column is simply one
/// card shorter.
///
/// Flow preserves the V1 wiring:
/// 1. Notifications card → tapping the card calls
///    `AlarmScheduler.requestPermission` with the same option ladder used at
///    AppDelegate launch.
/// 2. Background — `UIBackgroundModes` is declared in Info.plist for the
///    audio playback / processing categories, so this card is informational
///    and renders as granted.
///
/// Persistence: `permissions_screen_shown` UserDefaults key prevents re-show
/// on subsequent launches even when the user picks "Готово" without granting
/// anything. Future grants / revocations happen through Settings; the screen
/// does not nag.
final class PermissionsViewController: UIViewController {

    // MARK: - Persistence keys

    /// Tracks whether the permissions screen has been dismissed at least
    /// once. Exposed at module-level so the debug "reset onboarding" entry in
    /// AlarmsListVC can clear it alongside the onboarding-completed flag.
    static let hasBeenShownKey = "permissions_screen_shown"

    /// `true` once the user has dismissed the permissions screen at least
    /// once (either by granting or via "Готово"). Read by SceneDelegate to
    /// decide whether to present the screen on a given launch.
    static var hasBeenShown: Bool {
        UserDefaults.standard.bool(forKey: hasBeenShownKey)
    }

    // MARK: - Callback

    /// Invoked once the user finishes (grant complete or "Готово"). SceneDelegate
    /// uses this to swap the root from this VC to the tab bar.
    var onFinished: (() -> Void)?

    // MARK: - State

    private var notificationStatus: UNAuthorizationStatus = .notDetermined

    // MARK: - Subviews

    private let capsLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.attributedText = NSAttributedString(
            string: "ПОСЛЕДНИЙ ШАГ",
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: AppColors.warn300
            ]
        )
        return label
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Чтобы будильник работал"
        label.font = AppTypography.h1
        label.textColor = .white
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = false
        // -0.02em at 32pt ≈ -0.64; clamp to -0.32 per spec direction so it
        // tightens without bleeding into adjacent glyphs.
        label.attributedText = NSAttributedString(
            string: "Чтобы будильник работал",
            attributes: [
                .font: AppTypography.h1,
                .kern: -0.32,
                .foregroundColor: UIColor.white
            ]
        )
        return label
    }()

    private let bodyLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Эти разрешения нужны, чтобы будильник прозвенел даже на беззвучном режиме."
        label.font = AppTypography.bodyLg
        label.textColor = AppColors.fg2
        label.numberOfLines = 0
        return label
    }()

    private let cardsStack: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = AppSpacing.sp3
        stack.alignment = .fill
        return stack
    }()

    private let ctaButton = SPButton(
        title: "Готово",
        variant: .money,
        size: .lg,
        fullWidth: true
    )

    /// Vertical scroll container so the caps/title/body/cards/CTA column can
    /// overflow and scroll on compact-height devices or large Dynamic Type
    /// instead of breaking the `cta.bottom <= safeArea` constraint and clipping
    /// the CTA under the home indicator (#409). Mirrors the adaptive-overflow
    /// intent of the onboarding rework (#244). On tall devices the content fits
    /// the frame and the view reads identically to before.
    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = false
        // Keep the column width fixed to the frame; never inset horizontally so
        // the cards stay edge-aligned with the JSX 16pt side padding.
        scrollView.contentInsetAdjustmentBehavior = .never
        return scrollView
    }()

    /// One card per `PermissionKind`, owned so we can re-render trailing
    /// affordances after a grant without rebuilding the view tree.
    private var cardViews: [PermissionKind: PermissionCardView] = [:]

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        // Force dark — onboarding flow is canonically dark regardless of the
        // system theme so the warn / money brand stops read consistently.
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = AppColors.bg0
        setupUI()
        refreshNotificationSettings()
        ctaButton.accessibilityIdentifier = "permissions.doneButton"
        ctaButton.addTarget(self, action: #selector(ctaTapped), for: .touchUpInside)
    }

    override var prefersStatusBarHidden: Bool { false }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Refresh on every appear so a return-from-Settings flips the cards
        // without the user having to relaunch the app.
        refreshNotificationSettings()
    }

    // MARK: - Setup

    private func setupUI() {
        view.addSubview(scrollView)
        scrollView.addSubview(capsLabel)
        scrollView.addSubview(titleLabel)
        scrollView.addSubview(bodyLabel)
        scrollView.addSubview(cardsStack)
        scrollView.addSubview(ctaButton)
        ctaButton.translatesAutoresizingMaskIntoConstraints = false

        let inset = AppSpacing.sp4   // 16pt — matches JSX `padding: 70px 16px 52px`
        let content = scrollView.contentLayoutGuide
        let frame = scrollView.frameLayoutGuide

        // Min content height equal to the visible frame so a short column stays
        // top-aligned (no centering) and reads identically to the pre-scroll
        // layout on tall devices. On overflow the content guide grows past the
        // frame and the column scrolls.
        let minHeight = content.heightAnchor.constraint(equalTo: frame.heightAnchor)
        minHeight.priority = .defaultLow

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            // Pin the column width to the visible frame so labels wrap to the
            // device width rather than the scroll content's intrinsic size.
            content.widthAnchor.constraint(equalTo: frame.widthAnchor),
            minHeight,

            // JSX top pad 70 on a 54pt-status-bar frame ⇒ 16pt below the
            // safe-area top.
            capsLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: AppSpacing.sp4),
            capsLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: inset),
            capsLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: content.trailingAnchor,
                constant: -inset
            ),

            titleLabel.topAnchor.constraint(equalTo: capsLabel.bottomAnchor, constant: AppSpacing.sp2),
            titleLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: inset),
            titleLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -inset),

            bodyLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: AppSpacing.sp3),
            bodyLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: inset),
            bodyLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -inset),

            cardsStack.topAnchor.constraint(equalTo: bodyLabel.bottomAnchor, constant: AppSpacing.sp7),
            cardsStack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: inset),
            cardsStack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -inset),

            ctaButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: inset),
            ctaButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -inset),
            // V3: "Готово" lives in flow 28pt after the cards (JSX
            // `marginTop: 28`) instead of pinning to the screen bottom —
            // cards no longer flex-grow into the gap.
            ctaButton.topAnchor.constraint(
                equalTo: cardsStack.bottomAnchor,
                constant: AppSpacing.sp6 + AppSpacing.sp1   // 28pt
            ),
            // Bottom pad mirrors the JSX 52px bottom (≈ 18pt above the
            // home-indicator inset). Drives the scroll content height so the
            // CTA stays reachable instead of clipping on compact heights.
            ctaButton.bottomAnchor.constraint(
                equalTo: content.bottomAnchor,
                constant: -(AppSpacing.sp4 + 2)   // 18pt
            )
        ])

        for kind in [PermissionKind.notifications, .sound] {
            let card = PermissionCardView(kind: kind)
            card.onPrimaryTap = { [weak self] in self?.handleGrantTap(for: kind) }
            cardViews[kind] = card
            cardsStack.addArrangedSubview(card)
        }
    }

    // MARK: - State refresh

    /// Fetch the current `UNNotificationSettings` and re-render every card.
    /// Always dispatches back to main — UN settings callbacks fire on a
    /// background queue.
    private func refreshNotificationSettings() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.notificationStatus = settings.authorizationStatus
                self.applyStatusToCards()
            }
        }
    }

    private func applyStatusToCards() {
        cardViews[.notifications]?.apply(status: notificationsStatus())
        cardViews[.sound]?.apply(status: soundStatus())
    }

    private func notificationsStatus() -> PermissionStatus {
        Self.notificationPermissionStatus(for: notificationStatus)
    }

    /// Uses the same alarm-safety interpretation as
    /// `SystemAlarmBackendProbe`: only a fully authorized notification can
    /// wake someone. Provisional and ephemeral delivery must stay actionable,
    /// not receive the green "granted" treatment.
    static func notificationPermissionStatus(
        for notificationStatus: UNAuthorizationStatus
    ) -> PermissionStatus {
        switch notificationStatus {
        case .authorized:
            return .granted
        case .denied, .notDetermined, .provisional, .ephemeral:
            return .actionable
        @unknown default:
            return .actionable
        }
    }

    private func soundStatus() -> PermissionStatus {
        // `UIBackgroundModes` is declared in Info.plist for audio playback /
        // processing — the system grants it implicitly. No user action exists.
        .enabled
    }

    // MARK: - Grant flow

    private func handleGrantTap(for kind: PermissionKind) {
        switch kind {
        case .notifications:
            handleNotificationsTap()
        case .sound:
            // Background mode card is informational — no tap path.
            break
        }
    }

    private func handleNotificationsTap() {
        if notificationStatus == .denied {
            openAppSettings()
            return
        }
        // Route through `AlarmScheduler.requestPermission` so the same
        // request ladder runs as on AppDelegate launch.
        AlarmScheduler.shared.requestPermission { [weak self] _ in
            // Refresh from settings rather than trusting the `granted` flag
            // alone — the authorization status is the value the cards render.
            self?.refreshNotificationSettings()
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - CTA

    @objc
    private func ctaTapped() {
        UserDefaults.standard.set(true, forKey: Self.hasBeenShownKey)
        onFinished?()
    }
}
