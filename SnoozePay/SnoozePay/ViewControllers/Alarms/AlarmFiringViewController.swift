import UIKit

/// Fullscreen alarm firing screen.
/// Dark background with decorative purple gradient circles,
/// large time display, alarm name, and two pill-shaped action buttons with icons.
class AlarmFiringViewController: UIViewController {

    // MARK: - ViewModel

    private let viewModel: AlarmFiringViewModel

    // MARK: - UI Elements

    /// Blurred background — simulates the iOS lock screen wallpaper blur
    private let blurView: UIVisualEffectView = {
        let blur = UIBlurEffect(style: .systemUltraThinMaterialDark)
        let view = UIVisualEffectView(effect: blur)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    /// Decorative purple circle — top left area
    private let topLeftCircle: UIView = {
        let size: CGFloat = 200
        let circle = UIView(frame: CGRect(x: -40, y: -20, width: size, height: size))
        circle.backgroundColor = UIColor(red: 0.55, green: 0.30, blue: 0.85, alpha: 0.40)
        circle.layer.cornerRadius = size / 2
        circle.layer.masksToBounds = true
        return circle
    }()

    /// Decorative purple circle — bottom right area
    private let bottomRightCircle: UIView = {
        let size: CGFloat = 150
        let circle = UIView(frame: CGRect(x: 0, y: 0, width: size, height: size))
        circle.backgroundColor = UIColor(red: 0.55, green: 0.30, blue: 0.85, alpha: 0.30)
        circle.layer.cornerRadius = size / 2
        circle.layer.masksToBounds = true
        return circle
    }()

    /// "БУДИЛЬНИК" label at top (matches native iOS alarm)
    private let alarmTypeLabel: UILabel = {
        let label = UILabel()
        let title = "БУДИЛЬНИК"
        let attributed = NSAttributedString(
            string: title,
            attributes: [.kern: 2]
        )
        label.attributedText = attributed
        label.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        label.textColor = UIColor.white.withAlphaComponent(0.6)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    /// Large time display (96pt Light — matches native iOS alarm)
    private let timeLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 96, weight: .thin)
        label.textColor = .white
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    /// Alarm name subtitle
    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 20, weight: .regular)
        label.textColor = UIColor.white.withAlphaComponent(0.7)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    /// "Выключить" — light gray pill with xmark icon
    private let dismissButton: UIButton = {
        // #EBEBF0 at 60% opacity
        let bgColor = UIColor(red: 0.92, green: 0.92, blue: 0.94, alpha: 0.60)

        var config = UIButton.Configuration.filled()
        config.title = "Выключить"
        config.image = UIImage(systemName: "xmark")
        config.imagePadding = 8
        config.imagePlacement = .leading
        config.baseBackgroundColor = bgColor
        config.baseForegroundColor = .white
        config.cornerStyle = .capsule
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
            var updated = attrs
            updated.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
            return updated
        }
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    /// "Отложить · X₽" — golden/warm orange pill with bell icon
    private let snoozeButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.image = UIImage(systemName: "bell.fill")
        config.imagePadding = 8
        config.imagePlacement = .leading
        config.baseBackgroundColor = AppColors.alarmFiringSnooze
        config.baseForegroundColor = .white
        config.cornerStyle = .capsule
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
            var updated = attrs
            updated.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
            return updated
        }
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    /// Banner shown when AudioService falls back to vibration / silent mode.
    /// Hidden by default; surfaces only on `.silentBecauseConfigFailed` or `.vibrationOnly`.
    private let audioWarningBanner: UILabel = {
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
        // Accessibility: VoiceOver reads the warning even if user can't see banner.
        label.isAccessibilityElement = true
        label.accessibilityTraits = [.staticText, .updatesFrequently]
        return label
    }()

    /// Timer to update displayed time each second
    private var clockTimer: Timer?

    /// Observer token for `AudioService.stateChangedNotification`. Kept so we
    /// can remove the observer in `deinit` and avoid leaking blocks across
    /// presentations of this screen.
    private var audioStateObserver: NSObjectProtocol?

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
        setupUI()
        bindViewModel()
        observeAudioState()
        startClock()
        startPulseAnimation()

        // Start continuous alarm sound and vibration. State observer (above)
        // will surface the banner if AudioService falls back to vibration-only
        // or fails to acquire the audio session.
        AudioService.shared.startAlarmSound(soundID: viewModel.alarm.soundID)

        // Sync UI with whatever state startAlarmSound produced — observer fires
        // on transitions, but the very first transition may have already
        // happened above before we begin observing on the next runloop tick.
        applyAudioState(AudioService.shared.state)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        clockTimer?.invalidate()

        // Stop the repeating pulse animation explicitly so the
        // animator does not retain self past dismissal.
        nameLabel.layer.removeAllAnimations()

        // Stop alarm sound and vibration when screen is dismissed
        AudioService.shared.stopAlarmSound()
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = .black

        // Background blur
        view.addSubview(blurView)
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: view.topAnchor),
            blurView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // Decorative gradient circles
        view.addSubview(topLeftCircle)
        view.addSubview(bottomRightCircle)

        // Content
        view.addSubview(alarmTypeLabel)
        view.addSubview(timeLabel)
        view.addSubview(nameLabel)

        // Buttons side by side
        let buttonStack = UIStackView(arrangedSubviews: [dismissButton, snoozeButton])
        buttonStack.axis = .horizontal
        buttonStack.distribution = .fillEqually
        buttonStack.spacing = 12
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(buttonStack)

        // Audio fallback warning — sits just above the buttons so the user sees
        // it without scrolling past the prominent time display.
        view.addSubview(audioWarningBanner)

        NSLayoutConstraint.activate([
            // ALARM label — near top safe area
            alarmTypeLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            alarmTypeLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            // Time — center ish, shifted up from middle
            timeLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            timeLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -80),
            timeLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            timeLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            // Alarm name below time
            nameLabel.topAnchor.constraint(equalTo: timeLabel.bottomAnchor, constant: 8),
            nameLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            // Audio warning banner — above the buttons, full width with margins
            audioWarningBanner.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            audioWarningBanner.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            audioWarningBanner.bottomAnchor.constraint(equalTo: buttonStack.topAnchor, constant: -16),

            // Buttons — pinned to bottom safe area
            buttonStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            buttonStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            buttonStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            buttonStack.heightAnchor.constraint(equalToConstant: 80)
        ])

        dismissButton.addTarget(self, action: #selector(dismissTapped), for: .touchUpInside)
        snoozeButton.addTarget(self, action: #selector(snoozeTapped), for: .touchUpInside)

        updateUI()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Position decorative circles relative to screen bounds
        let bounds = view.bounds
        topLeftCircle.frame = CGRect(x: -40, y: bounds.height * 0.10, width: 200, height: 200)
        bottomRightCircle.frame = CGRect(
            x: bounds.width - 110,
            y: bounds.height * 0.65,
            width: 150,
            height: 150
        )

    }

    private func bindViewModel() {
        viewModel.onStateChanged = { [weak self] in
            self?.updateUI()
        }
    }

    /// Observe `AudioService.stateChangedNotification` and reflect the new state
    /// in the warning banner. Notification is posted on the main queue by the
    /// service, so no extra hop is needed.
    private func observeAudioState() {
        audioStateObserver = NotificationCenter.default.addObserver(
            forName: AudioService.stateChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard
                let self,
                let newState = note.userInfo?[AudioService.stateUserInfoKey] as? AudioPlaybackState
            else { return }
            self.applyAudioState(newState)
        }
    }

    /// Surface (or hide) the warning banner depending on AudioService state.
    /// Decoupled from `observeAudioState` so we can call it once after
    /// `startAlarmSound` to catch the synchronous initial transition.
    private func applyAudioState(_ newState: AudioPlaybackState) {
        switch newState {
        case .playing, .stopped:
            audioWarningBanner.isHidden = true
            audioWarningBanner.text = nil
            audioWarningBanner.accessibilityLabel = nil
        case .silentBecauseConfigFailed:
            let text = "Звук недоступен — другое приложение использует аудио. " +
                "Проверьте режим звука."
            audioWarningBanner.text = "  \(text)  "
            audioWarningBanner.accessibilityLabel = text
            audioWarningBanner.isHidden = false
        case .vibrationOnly:
            let text = "Звук не воспроизводится — будильник вибрирует."
            audioWarningBanner.text = "  \(text)  "
            audioWarningBanner.accessibilityLabel = text
            audioWarningBanner.isHidden = false
        }
    }

    private func updateUI() {
        nameLabel.text = viewModel.alarmName

        // Snooze button title (with config to preserve icon)
        var snoozeConfig = snoozeButton.configuration
        snoozeConfig?.title = viewModel.snoozeButtonTitle

        if viewModel.canSnooze {
            snoozeConfig?.baseBackgroundColor = AppColors.alarmFiringSnooze
            snoozeButton.configuration = snoozeConfig
            snoozeButton.isEnabled = true
        } else {
            snoozeConfig?.baseBackgroundColor = UIColor.systemGray.withAlphaComponent(0.5)
            snoozeButton.configuration = snoozeConfig
            snoozeButton.isEnabled = false
        }
    }

    // MARK: - Clock

    private func startClock() {
        updateTime()
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateTime()
        }
    }

    /// Cached formatter — updateTime() runs once per second; rebuilding a
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

    // MARK: - Pulse animation

    private func startPulseAnimation() {
        UIView.animate(
            withDuration: 1.4,
            delay: 0,
            options: [.autoreverse, .repeat, .allowUserInteraction],
            animations: { [weak self] in
                self?.nameLabel.alpha = 0.5
            }
        )
    }

    // MARK: - Actions

    @objc private func dismissTapped() {
        viewModel.dismiss()
        dismiss(animated: true)
    }

    @objc private func snoozeTapped() {
        let success = viewModel.snooze()
        if success {
            dismiss(animated: true)
        }
        // If failed (balance empty) — button is already disabled, nothing to do
    }
}
