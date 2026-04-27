import UIKit
import os

/// Fullscreen alarm firing screen — Dawn redesign (#138).
///
/// Replaces the previous iOS-blur + decorative purple circles with the
/// design-refresh "Dawn" treatment: a vertical 4-stop atmospheric gradient
/// (`--sp-grad-dawn`), a slow-breathing warm radial glow at the bottom, a
/// 96pt mono clock, and a large warn-toned snooze CTA backed by
/// `SPSnoozePrice`. The dismiss action degrades to a ghost button below
/// the snooze so the visual hierarchy steers the half-asleep user toward
/// the paid action while keeping "Я встал" reachable.
///
/// Existing audio + coordinator wiring (AudioService stacking guard,
/// vibration-fallback banner, snooze schedule failure alert) is preserved
/// verbatim — this PR is a visual rework, not a behaviour change.
class AlarmFiringViewController: UIViewController {

    // MARK: - ViewModel

    /// `internal` so the +Audio and +Progressive extensions in sibling files
    /// can read VM state during their UI updates.
    let viewModel: AlarmFiringViewModel

    // MARK: - Background layers

    /// Dawn 180° gradient sourced from `--sp-grad-dawn` in `tokens.css`:
    /// #14122A → #0F1A2E (40%) → #0A1320 (70%) → #050912.
    private let dawnGradientLayer: CAGradientLayer = {
        let gradient = CAGradientLayer()
        gradient.colors = [
            UIColor(rgb: 0x14122A).cgColor,
            UIColor(rgb: 0x0F1A2E).cgColor,
            UIColor(rgb: 0x0A1320).cgColor,
            UIColor(rgb: 0x050912).cgColor
        ]
        gradient.locations = [0.0, 0.4, 0.7, 1.0]
        gradient.startPoint = CGPoint(x: 0.5, y: 0.0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1.0)
        return gradient
    }()

    /// Warm radial glow anchored below the bottom edge — a warn500-flavoured
    /// halo that "breathes" via a 4s opacity animation.
    private let warmGlowLayer: CAGradientLayer = {
        let gradient = CAGradientLayer()
        gradient.type = .radial
        gradient.colors = [
            UIColor(rgb: 0xF59E0B, alpha: 0.22).cgColor,
            UIColor(rgb: 0xF59E0B, alpha: 0.10).cgColor,
            UIColor(rgb: 0xF59E0B, alpha: 0.0).cgColor
        ]
        gradient.locations = [0.0, 0.5, 1.0]
        gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradient.endPoint = CGPoint(x: 1.0, y: 1.0)
        return gradient
    }()

    // MARK: - Content

    /// 96pt mono clock — `AppTypography.clockXl` with `.monospacedDigit()`
    /// so digit columns don't reflow on each tick.
    private let timeLabel: UILabel = {
        let label = UILabel()
        label.font = AppTypography.clockXl.monospacedDigit()
        label.textColor = AppColors.fg1
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = AppTypography.bodyLg
        label.textColor = AppColors.fg2
        label.textAlignment = .center
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    /// Big snooze CTA. Built in `setupUI` because its constructor needs
    /// VM-derived price + minutes that aren't valid at property-init time.
    /// Tone defaults to `.warn`; for `progressiveScale == true` alarms the
    /// VC swaps it to `.progressive(intensity:)` and bumps the intensity on
    /// every snooze tap (#139). `internal` so the +Progressive extension
    /// can re-tone it on `updateUI()`.
    var snoozeCTA: SPSnoozePrice?

    private let dismissButton = SPButton(
        title: "Я встал",
        variant: .ghost,
        size: .lg,
        fullWidth: true
    )

    // MARK: - Progressive UI (#139) — only mounted when `alarm.progressiveScale`.
    //
    // Layout + animation logic lives in `AlarmFiringViewController+Progressive.swift`;
    // these stored handles are accessed from the extension via `internal` so the
    // type body of the main VC stays under SwiftLint's `type_body_length` cap.

    /// Container holding the indicator pill + history ticker. Built lazily
    /// inside `setupUI` so the default firing flow (#138) skips both views
    /// entirely — they never enter the layout pass.
    var progressiveStack: UIStackView?

    /// "Прогрессив · N-й снуз" pill above the snooze CTA. Re-titled on every
    /// `updateUI()` so the label tracks `snoozeCount + 1` (the next snooze).
    var progressivePill: SPPill?

    /// Pulsing dot rendered inside `progressivePill`. CABasicAnimation lives
    /// on its `layer.opacity` (autoreverse, infinite, 900ms — `--sp-dur-anxious`).
    var progressivePulseDot: UIView?

    /// Single-line ticker rendered between the pill and the snooze CTA.
    /// `meta` typography, fg-3, mono digits — "сегодня: −50 → −100 → ..."
    /// Hidden when `snoozeCount == 0` (no history to show yet).
    var historyTicker: UILabel?

    /// Banner shown when AudioService falls back to vibration / silent mode.
    /// Hidden by default; surfaces only on `.silentBecauseConfigFailed` or `.vibrationOnly`.
    /// `internal` so the AudioState extension in the sibling file can update it.
    let audioWarningBanner: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        label.backgroundColor = UIColor(red: 0.86, green: 0.27, blue: 0.27, alpha: 0.85)
        label.layer.cornerRadius = 10
        label.layer.masksToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        label.isAccessibilityElement = true
        label.accessibilityTraits = [.staticText, .updatesFrequently]
        return label
    }()

    private var clockTimer: Timer?

    /// Observer token for `AudioService.stateChangedNotification`. Removed
    /// in `deinit` so blocks don't leak across screen presentations.
    /// `internal` so the AudioState extension in the sibling file can write it.
    var audioStateObserver: NSObjectProtocol?

    // MARK: - Init

    init(alarm: Alarm, snoozeCount: Int = 0) {
        self.viewModel = AlarmFiringViewModel(alarm: alarm, snoozeCount: snoozeCount)
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let token = audioStateObserver {
            NotificationCenter.default.removeObserver(token)
        }
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        // Per `tokens.css` lines 109–112 and reaffirmed by #136: the firing
        // screen is intentionally exempt from the brand light theme. Pin
        // `.dark` so the system theme can't bleed through.
        overrideUserInterfaceStyle = .dark
        setupUI()
        bindViewModel()
        observeAudioState()
        startClock()
        startGlowBreathing()

        // Pass `alarmID` so a stacking-replace race (#116) does not silence
        // the next alarm when this VC's `viewDidDisappear` fires.
        AudioService.shared.startAlarmSound(
            soundID: viewModel.alarm.soundID,
            alarmID: viewModel.alarm.id
        )

        // Initial transition may have happened synchronously inside
        // `startAlarmSound` before our observer is wired — sync now.
        applyAudioState(AudioService.shared.state)

        #if DEBUG
        installDebugTopUpButton()
        #endif
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        clockTimer?.invalidate()
        warmGlowLayer.removeAllAnimations()

        // Stop alarm sound only if AudioService still belongs to *this*
        // alarm. Stacking handoff (alarm B fires while A is on-screen)
        // could otherwise silence B (#116).
        if AudioService.shared.currentAlarmID == viewModel.alarm.id {
            AudioService.shared.stopAlarmSound()
        } else {
            let ownerDesc = String(describing: AudioService.shared.currentAlarmID)
            let ours = self.viewModel.alarm.id
            AppLogger.audio.notice(
                "viewDidDisappear: skip stop — owner=\(ownerDesc, privacy: .private), ours=\(ours, privacy: .private)"
            )
        }
    }

    override var prefersStatusBarHidden: Bool { false }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = UIColor(rgb: 0x050912)
        view.layer.insertSublayer(dawnGradientLayer, at: 0)
        view.layer.insertSublayer(warmGlowLayer, at: 1)

        // VM exposes `currentPenalty` as `Double`; wrap in `Decimal` so
        // `SPSnoozePrice.formattedRubles()` does the locale-aware format.
        // Pick the initial tone based on the alarm config — progressive
        // alarms start at intensity 0 (still pure warn) and ramp up as the
        // user snoozes.
        let initialTone: SPSnoozePrice.Tone = viewModel.isProgressiveActive
            ? .progressive(intensity: viewModel.progressiveIntensity)
            : .warn
        let snooze = SPSnoozePrice(
            price: Decimal(viewModel.currentPenalty),
            minutes: viewModel.alarm.snoozeMinutes,
            tone: initialTone,
            hint: nil
        )
        snooze.translatesAutoresizingMaskIntoConstraints = false
        snooze.onTap = { [weak self] in self?.snoozeTapped() }
        view.addSubview(snooze)
        snoozeCTA = snooze

        view.addSubview(timeLabel)
        view.addSubview(nameLabel)

        dismissButton.translatesAutoresizingMaskIntoConstraints = false
        dismissButton.addTarget(self, action: #selector(dismissTapped), for: .touchUpInside)
        view.addSubview(dismissButton)
        view.addSubview(audioWarningBanner)

        let inset: CGFloat = AppSpacing.sp5      // 20pt — Dawn spec
        let gap: CGFloat = AppSpacing.sp3         // 12pt — Dawn spec

        // Progressive escalation chrome — only mounted for alarms with the
        // doubling-penalty toggle. The default flow stays exactly as #138.
        // Anchor the audio-fallback banner to the chrome's top so the banner
        // never overlaps the indicator when both are on screen.
        let bannerBottomAnchor: NSLayoutYAxisAnchor
        if viewModel.isProgressiveActive {
            let stack = installProgressiveStack(inset: inset)
            NSLayoutConstraint.activate([
                stack.bottomAnchor.constraint(equalTo: snooze.topAnchor, constant: -AppSpacing.sp3)
            ])
            bannerBottomAnchor = stack.topAnchor
        } else {
            bannerBottomAnchor = snooze.topAnchor
        }

        NSLayoutConstraint.activate([
            timeLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            timeLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -80),
            timeLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: inset),
            timeLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -inset),

            nameLabel.topAnchor.constraint(equalTo: timeLabel.bottomAnchor, constant: AppSpacing.sp2),
            nameLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            nameLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: inset),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -inset),

            audioWarningBanner.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: inset),
            audioWarningBanner.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -inset),
            audioWarningBanner.bottomAnchor.constraint(equalTo: bannerBottomAnchor, constant: -AppSpacing.sp4),

            snooze.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: inset),
            snooze.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -inset),
            snooze.bottomAnchor.constraint(equalTo: dismissButton.topAnchor, constant: -gap),

            dismissButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: inset),
            dismissButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -inset),
            dismissButton.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -AppSpacing.sp6
            )
        ])

        updateUI()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        dawnGradientLayer.frame = view.bounds

        // Glow anchored below the bottom edge — only the upper hemisphere
        // of the radial bleeds into view.
        let bounds = view.bounds
        let glowSize = CGSize(width: bounds.width * 1.2, height: bounds.height * 0.6)
        warmGlowLayer.frame = CGRect(
            x: -(glowSize.width - bounds.width) / 2,
            y: bounds.height - glowSize.height * 0.55,
            width: glowSize.width,
            height: glowSize.height
        )
    }

    private func bindViewModel() {
        viewModel.onStateChanged = { [weak self] in
            self?.updateUI()
        }
    }

    func updateUI() {
        nameLabel.text = viewModel.alarmName

        // Refresh snooze CTA — VM may have bumped `snoozeCount` (progressive
        // scaling) since the last update, which changes `currentPenalty`.
        if let snooze = snoozeCTA {
            snooze.update(
                price: Decimal(viewModel.currentPenalty),
                minutes: viewModel.alarm.snoozeMinutes,
                hint: nil
            )
            snooze.isEnabled = viewModel.canSnooze
            if viewModel.isProgressiveActive {
                // Cross-fade the gradient toward pain as snoozeCount climbs.
                // SPSnoozePrice.setTone is a no-op when intensity hasn't
                // moved, so calling it on every updateUI() is cheap.
                snooze.setTone(.progressive(intensity: viewModel.progressiveIntensity))
            }
        }

        if viewModel.isProgressiveActive {
            updateProgressiveChrome()
        }
    }

    // MARK: - Clock

    private func startClock() {
        updateTime()
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateTime()
        }
    }

    /// Cached formatter — `updateTime()` runs once per second; rebuilding a
    /// DateFormatter each tick is ~1ms wasted. Locale fixed to `en_US_POSIX`
    /// so `HH:mm` is honoured regardless of the user's region.
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private func updateTime() {
        timeLabel.text = Self.timeFormatter.string(from: Date())
    }

    // MARK: - Glow breathing

    /// 4s ease-in-out autoreverse opacity pulse on the warm glow. Driven via
    /// CABasicAnimation because the glow is a CAGradientLayer (not a view).
    private func startGlowBreathing() {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 0.55
        animation.toValue = 1.0
        animation.duration = 4.0
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.autoreverses = true
        animation.repeatCount = .infinity
        warmGlowLayer.add(animation, forKey: "breathing")
    }

    // MARK: - Actions

    @objc private func dismissTapped() {
        viewModel.dismiss()
        dismiss(animated: true)
    }

    private func snoozeTapped() {
        // scheduleCompletion surfaces a notification-center failure (revoked
        // permission, 64-pending-limit, malformed trigger) so the user
        // doesn't pay for a snooze that will never re-fire (#127 finding).
        let success = viewModel.snooze { [weak self] result in
            guard let self else { return }
            if case let .failure(error) = result {
                self.presentSnoozeScheduleFailureAlert(error: error)
            }
        }
        if success {
            dismiss(animated: true)
        }
    }

    // MARK: - Top-up sheet (#141)

    /// Present the firing-time top-up bottom sheet. Public entry point so the
    /// no-balance UX (#140) can wire it into the snooze affordance once the
    /// firing VC rewrite (#138) lands. Pause/resume of the alarm audio +
    /// escalation is owned by the sheet itself via `AlarmFiringCoordinator
    /// .pauseEscalation()`, so callers don't need to coordinate audio state.
    func presentTopUpSheet() {
        let sheet = FiringTopUpBottomSheetViewController()
        present(sheet, animated: true)
    }

    #if DEBUG
    /// Debug-only floating button for manually triggering the top-up sheet
    /// during development. Wired in `viewDidLoad` behind `#if DEBUG`. Removed
    /// once #140 hooks the trigger to the real "balance < snooze price" UX.
    private lazy var debugTopUpButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "DEBUG: Top-up"
        config.baseBackgroundColor = UIColor.systemPurple.withAlphaComponent(0.6)
        config.baseForegroundColor = .white
        config.cornerStyle = .capsule
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(debugTopUpTapped), for: .touchUpInside)
        return button
    }()

    @objc private func debugTopUpTapped() {
        presentTopUpSheet()
    }

    /// Installs the debug top-up button. Called from `viewDidLoad` only in
    /// DEBUG builds so the production binary never carries the affordance.
    private func installDebugTopUpButton() {
        view.addSubview(debugTopUpButton)
        NSLayoutConstraint.activate([
            debugTopUpButton.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: 8
            ),
            debugTopUpButton.trailingAnchor.constraint(
                equalTo: view.trailingAnchor,
                constant: -16
            )
        ])
    }
    #endif

    private func presentSnoozeScheduleFailureAlert(
        error: AlarmScheduler.SchedulingError
    ) {
        let detail = error.errorDescription ?? error.localizedDescription
        let alert = UIAlertController(
            title: "Снуз не запланирован",
            message: "\(detail) Будильник не зазвенит повторно — установите запасной.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Ок", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - Hex helper

private extension UIColor {
    /// `0xRRGGBB` literal initializer so the Dawn gradient stops read as in
    /// `tokens.css`. Local copy mirroring the (private) helper in AppColors.
    convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        let red = CGFloat((rgb >> 16) & 0xFF) / 255.0
        let green = CGFloat((rgb >> 8) & 0xFF) / 255.0
        let blue = CGFloat(rgb & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}
