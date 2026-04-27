import UIKit
import UserNotifications

/// Permissions screen — shown once after Onboarding finishes, before the main
/// alarms list. Three permission cards (Notifications, Critical Alerts, Sound
/// in silent mode) plus a "Позже" footer.
///
/// Flow:
/// 1. Notifications card → tapping "Разрешить" calls
///    `UNUserNotificationCenter.requestAuthorization` with the same option set
///    `AlarmScheduler.requestPermission` uses (`alert + sound + badge +
///    criticalAlert`). On result the cards refresh.
/// 2. Critical Alerts — hard-gated on the entitlement living in
///    `SnoozePay.entitlements`. The entitlement is currently commented out
///    (PM-only), so the card surfaces a neutral "Недоступно" pill until it
///    lands. Once flipped, the same notification authorisation grant covers
///    both, so this card mirrors notifications status.
/// 3. Sound — `AVAudioSession` `.playback + .duckOthers`, no system permission
///    needed. `AudioService.configureAudioSession` already installs that
///    recipe on every alarm, so this card is informational ("Включено").
///
/// Persistence: `permissions_screen_shown` UserDefaults key prevents re-show
/// on subsequent launches even when the user picks "Позже". Future grants /
/// revocations happen through Settings; the screen does not nag.
final class PermissionsViewController: UIViewController {

    // MARK: - Persistence keys

    private static let shownKey = "permissions_screen_shown"

    /// `true` once the user has dismissed the permissions screen at least
    /// once (either by granting or via "Позже"). Read by SceneDelegate to
    /// decide whether to present the screen on a given launch.
    static var hasBeenShown: Bool {
        UserDefaults.standard.bool(forKey: shownKey)
    }

    // MARK: - Callback

    /// Invoked once the user finishes (grant complete or "Позже"). SceneDelegate
    /// uses this to swap the root from this VC to the tab bar.
    var onFinished: (() -> Void)?

    // MARK: - Background (Dawn)

    private let dawnGradientLayer: CAGradientLayer = {
        let gradient = CAGradientLayer()
        gradient.colors = [
            UIColor(permRGB: 0x14122A).cgColor,
            UIColor(permRGB: 0x0F1A2E).cgColor,
            UIColor(permRGB: 0x0A1320).cgColor,
            UIColor(permRGB: 0x050912).cgColor
        ]
        gradient.locations = [0.0, 0.4, 0.7, 1.0]
        gradient.startPoint = CGPoint(x: 0.5, y: 0.0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1.0)
        return gradient
    }()

    // MARK: - State

    /// Latest `UNNotificationSettings.authorizationStatus`. Drives the
    /// Notifications + Critical Alerts cards. Refreshed in `viewWillAppear`
    /// so a return-from-Settings flips the cards without manual re-launch.
    private var notificationStatus: UNAuthorizationStatus = .notDetermined

    /// Whether the Critical Alerts entitlement is *available* at all (i.e.
    /// the entitlement key is present in `.entitlements`). Detected via the
    /// `criticalAlertSetting` field on `UNNotificationSettings` — `.notSupported`
    /// means the entitlement isn't there, anything else means it is.
    ///
    /// Currently the entitlement is commented out in `SnoozePay.entitlements`
    /// (PM-only edit), so we expect `.notSupported` at runtime. Once PM
    /// uncomments the key, this will start tracking the actual grant state.
    private var criticalAlertsAvailable: Bool = false
    private var criticalAlertsGranted: Bool = false

    // MARK: - UI Elements

    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        return scrollView
    }()

    private let contentStack: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = AppSpacing.sp4
        stack.alignment = .fill
        return stack
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Разрешения"
        label.font = AppTypography.h1
        label.textColor = AppColors.fg1
        label.textAlignment = .left
        label.numberOfLines = 0
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Чтобы будильник работал — нужны несколько разрешений"
        label.font = AppTypography.bodyLg
        label.textColor = AppColors.fg2
        label.textAlignment = .left
        label.numberOfLines = 0
        return label
    }()

    /// Footer "Позже" — keeps the screen escapable even if the user never
    /// grants. Same persistence as the grant path so the screen does not
    /// re-show on next launch.
    private let laterButton = SPButton(
        title: "Позже",
        variant: .ghost,
        size: .lg,
        fullWidth: true
    )

    /// One card per `PermissionKind`, owned so we can re-render trailing
    /// affordances after a grant without rebuilding the view tree.
    private var cardViews: [PermissionKind: PermissionCardView] = [:]

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(permRGB: 0x050912)
        view.layer.insertSublayer(dawnGradientLayer, at: 0)
        setupUI()
        // Detect whether the Critical Alerts entitlement is even present
        // before we start fetching settings — `criticalAlertSetting` on a
        // missing entitlement is `.notSupported`.
        refreshNotificationSettings()
        laterButton.addTarget(self, action: #selector(laterTapped), for: .touchUpInside)
    }

    override var prefersStatusBarHidden: Bool { false }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Refresh on every appear so a return-from-Settings flips the cards
        // without the user having to relaunch the app.
        refreshNotificationSettings()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dawnGradientLayer.frame = view.bounds
        CATransaction.commit()
    }

    // MARK: - Setup

    private func setupUI() {
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)
        view.addSubview(laterButton)
        laterButton.translatesAutoresizingMaskIntoConstraints = false
        installLayoutConstraints()
        populateContent()
    }

    private func installLayoutConstraints() {
        let inset = AppSpacing.sp5
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: laterButton.topAnchor, constant: -AppSpacing.sp4),

            contentStack.topAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.topAnchor,
                constant: AppSpacing.sp6
            ),
            contentStack.leadingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.leadingAnchor,
                constant: inset
            ),
            contentStack.trailingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.trailingAnchor,
                constant: -inset
            ),
            contentStack.bottomAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.bottomAnchor,
                constant: -AppSpacing.sp6
            ),
            contentStack.widthAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.widthAnchor,
                constant: -inset * 2
            ),

            laterButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: inset),
            laterButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -inset),
            laterButton.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -inset
            )
        ])
    }

    private func populateContent() {
        contentStack.addArrangedSubview(titleLabel)
        contentStack.addArrangedSubview(subtitleLabel)
        contentStack.setCustomSpacing(AppSpacing.sp2, after: titleLabel)
        contentStack.setCustomSpacing(AppSpacing.sp6, after: subtitleLabel)

        for kind in [PermissionKind.notifications, .criticalAlerts, .sound] {
            let card = PermissionCardView(kind: kind)
            card.onPrimaryTap = { [weak self] in self?.handleGrantTap(for: kind) }
            cardViews[kind] = card
            contentStack.addArrangedSubview(card)
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
                // `.notSupported` means the Critical Alerts entitlement is
                // absent (e.g. it's commented out in `.entitlements`). Any
                // other value means the capability is wired and reflects the
                // actual user-grant state.
                self.criticalAlertsAvailable = settings.criticalAlertSetting != .notSupported
                self.criticalAlertsGranted = settings.criticalAlertSetting == .enabled
                self.applyStatusToCards()
            }
        }
    }

    private func applyStatusToCards() {
        cardViews[.notifications]?.apply(status: notificationsStatus())
        cardViews[.criticalAlerts]?.apply(status: criticalAlertsStatus())
        cardViews[.sound]?.apply(status: soundStatus())
    }

    private func notificationsStatus() -> PermissionStatus {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral:
            return .granted
        case .denied:
            // Once denied, the OS won't show the prompt again — the user
            // must flip the toggle in Settings. Surface the "Разрешить"
            // affordance anyway; the tap handler routes to Settings.
            return .actionable
        case .notDetermined:
            return .actionable
        @unknown default:
            return .actionable
        }
    }

    private func criticalAlertsStatus() -> PermissionStatus {
        guard criticalAlertsAvailable else {
            // Entitlement is missing from `.entitlements` — user cannot grant
            // this from the app. Documented in the PR description as a
            // follow-up for PM to flip the entitlement key.
            return .unavailable
        }
        return criticalAlertsGranted ? .granted : .actionable
    }

    private func soundStatus() -> PermissionStatus {
        // `AudioService.configureAudioSession` installs `.playback` +
        // `.duckOthers` every time an alarm starts ringing, so this is
        // always-on for the user. No system permission lives behind it.
        .enabled
    }

    // MARK: - Grant flow

    private func handleGrantTap(for kind: PermissionKind) {
        switch kind {
        case .notifications, .criticalAlerts:
            handleNotificationsTap()
        case .sound:
            // Sound card is informational — no tap path. `actionable` never
            // resolves for `.sound`, but guard defensively.
            break
        }
    }

    private func handleNotificationsTap() {
        // If the user already denied once, iOS won't re-prompt — open
        // Settings instead so they have a way to flip the toggle.
        if notificationStatus == .denied {
            openAppSettings()
            return
        }

        // Route through `AlarmScheduler.requestPermission` so the same
        // critical-alert-with-fallback request ladder runs as on AppDelegate
        // launch — and the `AlarmScheduler.criticalAlertsAvailable` static
        // flag stays in sync (it's `private(set)` so only the scheduler can
        // mutate it).
        AlarmScheduler.shared.requestPermission { [weak self] _ in
            // Refresh from settings rather than trusting the `granted` flag
            // alone — `criticalAlertSetting` may resolve differently from
            // the headline grant on legacy iOS versions.
            self?.refreshNotificationSettings()
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Footer actions

    @objc
    private func laterTapped() {
        finish()
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: Self.shownKey)
        onFinished?()
    }
}

// MARK: - Hex helper

private extension UIColor {
    /// `0xRRGGBB` literal initialiser, file-prefixed name to avoid collisions
    /// with the same helper inside Onboarding / Splash.
    convenience init(permRGB: UInt32, alpha: CGFloat = 1) {
        let red = CGFloat((permRGB >> 16) & 0xFF) / 255.0
        let green = CGFloat((permRGB >> 8) & 0xFF) / 255.0
        let blue = CGFloat(permRGB & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}
