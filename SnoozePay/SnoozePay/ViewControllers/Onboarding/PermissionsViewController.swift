import UIKit

/// AlarmKit permission explanation shared with the create/enable guard (#594).
/// Request permission while undecided; after refusal, lead to Settings.
/// Not Now enters the app in view-only mode. The monitor re-probes on activation
/// so returning from Settings updates the copy and primary action immediately.
final class PermissionsViewController: UIViewController {

    // MARK: - Persistence keys

    /// Tracks whether the permissions screen has been dismissed at least
    /// once. Exposed at module-level so the debug "reset onboarding" entry in
    /// AlarmsListVC can clear it alongside the onboarding-completed flag.
    static let hasBeenShownKey = "permissions_screen_shown"

    /// `true` once the user has dismissed the permissions screen at least
    /// once (after granting or via Not Now). Read by SceneDelegate to
    /// decide whether to present the screen on a given launch.
    static var hasBeenShown: Bool {
        UserDefaults.standard.bool(forKey: hasBeenShownKey)
    }

    // MARK: - Callback

    /// Invoked once the user finishes (grant complete or Not Now). SceneDelegate
    /// uses this to swap the root from this VC to the tab bar.
    var onFinished: (() -> Void)?

    // MARK: - State

    private let backendMonitor: AlarmBackendMonitor

    init(backendMonitor: AlarmBackendMonitor = AlarmBackendMonitor()) {
        self.backendMonitor = backendMonitor
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Subviews

    private let capsLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.attributedText = NSAttributedString(
            string: Localized.text("onboarding.permissions.caps"),
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
        label.text = Localized.text("onboarding.permissions.title")
        label.font = AppTypography.h1
        label.textColor = .white
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = false
        // -0.02em at 32pt ≈ -0.64; clamp to -0.32 per spec direction so it
        // tightens without bleeding into adjacent glyphs.
        label.attributedText = NSAttributedString(
            string: Localized.text("onboarding.permissions.title"),
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
        label.text = Localized.text("onboarding.permissions.body")
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

    private let actionsStack: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = AppSpacing.sp3
        return stack
    }()

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
        backendMonitor.onChange = { [weak self] _ in self?.applyStatusToCards() }
        refreshNotificationSettings()
        applyStatusToCards()
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
        scrollView.addSubview(actionsStack)

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

            actionsStack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: inset),
            actionsStack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -inset),
            // V3: «Готово» lives in flow 28pt after the cards (JSX
            // `marginTop: 28`) instead of pinning to the screen bottom —
            // cards no longer flex-grow into the gap.
            actionsStack.topAnchor.constraint(
                equalTo: cardsStack.bottomAnchor,
                constant: AppSpacing.sp6 + AppSpacing.sp1   // 28pt
            ),
            // Bottom pad mirrors the JSX 52px bottom (≈ 18pt above the
            // home-indicator inset). Drives the scroll content height so the
            // CTA stays reachable instead of clipping on compact heights.
            actionsStack.bottomAnchor.constraint(
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

    /// Re-read the grant; the monitor publishes changes on the main queue.
    private func refreshNotificationSettings() {
        backendMonitor.refresh()
    }

    private func applyStatusToCards() {
        let warning = AlarmBackendWarning(availability: backendMonitor.availability)
        cardViews[.notifications]?.apply(
            status: backendMonitor.availability == .available ? .granted : .actionable,
            actionTitle: warning?.canRequestInApp == false ? Localized.text("common.button.settings") : nil
        )
        cardViews[.sound]?.apply(status: soundStatus())
        titleLabel.attributedText = NSAttributedString(
            string: warning?.title ?? Localized.text("onboarding.permissions.title"),
            attributes: [.font: AppTypography.h1, .kern: -0.32, .foregroundColor: UIColor.white]
        )
        bodyLabel.text = warning?.message ?? Localized.text("onboarding.permissions.body")
        actionsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let primary = SPButton(
            title: warning?.actionTitle ?? Localized.text("common.button.done"),
            variant: .money, size: .lg, fullWidth: true
        )
        primary.accessibilityIdentifier = warning == nil ? "permissions.doneButton" : "permissions.allowButton"
        primary.addTarget(self, action: #selector(primaryTapped), for: .touchUpInside)
        actionsStack.addArrangedSubview(primary)
        if warning != nil {
            let later = SPButton(
                title: Localized.text("alarms.backend_guard.action.not_now"),
                variant: .quiet, size: .lg, fullWidth: true
            )
            later.accessibilityIdentifier = "permissions.notNowButton"
            later.addTarget(self, action: #selector(ctaTapped), for: .touchUpInside)
            actionsStack.addArrangedSubview(later)
        }
    }

    /// Uses the same interpretation as `SystemAlarmBackendProbe`: only an
    /// authorized alarm backend can wake someone, so every other state stays
    /// actionable rather than receiving the green "granted" treatment.
    static func alarmPermissionStatus(
        for authorization: AlarmKitAuthorization
    ) -> PermissionStatus {
        switch authorization {
        case .authorized:
            return .granted
        case .denied, .notDetermined, .unrecognized:
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
        backendMonitor.refresh()
        guard let warning = AlarmBackendWarning(availability: backendMonitor.availability) else { return }
        if warning.canRequestInApp {
            backendMonitor.requestAuthorization()
        } else {
            openAppSettings()
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - CTA

    @objc private func primaryTapped() {
        backendMonitor.refresh()
        if backendMonitor.availability == .available {
            ctaTapped()
        } else {
            handleNotificationsTap()
        }
    }

    @objc
    private func ctaTapped() {
        UserDefaults.standard.set(true, forKey: Self.hasBeenShownKey)
        onFinished?()
    }
}
