import UIKit

/// Fullscreen alarm firing screen.
/// Mirrors the native iOS 26 AlarmKit UI: blurred wallpaper background,
/// ALARM label at top, large time, alarm name, two frosted-glass buttons side-by-side.
/// The only customisation: Snooze button shows the penalty price.
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

    /// "Выключить" — green frosted glass, left side
    private let dismissButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "Выключить"
        config.baseBackgroundColor = UIColor(red: 0.19, green: 0.82, blue: 0.34, alpha: 0.85)
        config.baseForegroundColor = .white
        config.cornerStyle = .large
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
            var a = attrs
            a.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
            return a
        }
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    /// "Отложить · X₽" — orange frosted glass, right side
    private let snoozeButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = UIColor.systemOrange.withAlphaComponent(0.85)
        config.baseForegroundColor = .white
        config.cornerStyle = .large
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

    private func bindViewModel() {
        viewModel.onStateChanged = { [weak self] in
            self?.updateUI()
        }
    }

    private func updateUI() {
        nameLabel.text = viewModel.alarmName
        snoozeButton.setTitle(viewModel.snoozeButtonTitle, for: .normal)

        if viewModel.canSnooze {
            var config = snoozeButton.configuration
            config?.baseBackgroundColor = UIColor.systemOrange.withAlphaComponent(0.85)
            snoozeButton.configuration = config
            snoozeButton.isEnabled = true
        } else {
            var config = snoozeButton.configuration
            config?.baseBackgroundColor = UIColor.systemGray.withAlphaComponent(0.5)
            snoozeButton.configuration = config
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
