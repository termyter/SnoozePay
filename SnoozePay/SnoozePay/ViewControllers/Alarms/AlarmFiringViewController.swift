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
        label.text = "БУДИЛЬНИК"
        label.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        label.textColor = UIColor.white.withAlphaComponent(0.6)
        label.textAlignment = .center
        label.letterSpacing = 2
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
            var a = attrs
            a.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
            return a
        }
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    /// "Отложить · X₽" — golden/warm orange pill with bell icon
    private let snoozeButton: UIButton = {
        // #E8A838 warm orange/gold
        let activeColor = UIColor(red: 0.91, green: 0.66, blue: 0.22, alpha: 1.0)

        var config = UIButton.Configuration.filled()
        config.image = UIImage(systemName: "bell.fill")
        config.imagePadding = 8
        config.imagePlacement = .leading
        config.baseBackgroundColor = activeColor
        config.baseForegroundColor = .white
        config.cornerStyle = .capsule
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
            var a = attrs
            a.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
            return a
        }
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    /// Timer to update displayed time each second
    private var clockTimer: Timer?

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

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        bindViewModel()
        startClock()
        startPulseAnimation()

        // Start continuous alarm sound and vibration
        AudioService.shared.startAlarmSound(soundID: viewModel.alarm.soundID)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        clockTimer?.invalidate()

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

    private func updateUI() {
        nameLabel.text = viewModel.alarmName

        // Snooze button title (with config to preserve icon)
        var snoozeConfig = snoozeButton.configuration
        snoozeConfig?.title = viewModel.snoozeButtonTitle

        if viewModel.canSnooze {
            // #E8A838 warm orange/gold
            snoozeConfig?.baseBackgroundColor = UIColor(red: 0.91, green: 0.66, blue: 0.22, alpha: 1.0)
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

    private func updateTime() {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        timeLabel.text = formatter.string(from: Date())
    }

    // MARK: - Pulse animation

    private func startPulseAnimation() {
        UIView.animate(
            withDuration: 1.4,
            delay: 0,
            options: [.autoreverse, .repeat, .allowUserInteraction],
            animations: {
                self.nameLabel.alpha = 0.5
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

// MARK: - UILabel letter spacing helper

private extension UILabel {
    var letterSpacing: CGFloat {
        get { 0 }
        set {
            guard let text = text else { return }
            let attrs = NSMutableAttributedString(string: text)
            attrs.addAttribute(.kern, value: newValue, range: NSRange(location: 0, length: text.count))
            attributedText = attrs
        }
    }
}
