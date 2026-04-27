import UIKit

/// Full-screen picker for the per-alarm playback volume (#150).
///
/// Pushed onto the navigation stack from the create/edit alarm form. The
/// picker reports volume + fade-in changes back to the caller via the
/// `onChange` callback as the user manipulates the slider / switch — no
/// explicit "Save" action; the back chevron just pops the screen and the
/// most recent value is what sticks.
///
/// Layout follows the design-refresh handoff (`SPMore2.jsx` /
/// `SPMore4.jsx`):
///   - `SPCard(.surface)` preview at the top showing the live "{N}%"
///     reading in the `moneyXl` (56pt mono) numeric role.
///   - Money-tinted UISlider with 5%-step quantisation and a 28pt thumb.
///   - `SPRow` with an `SPSwitch` for the "Постепенно нарастает" / "За 30
///     секунд" fade-in option.
final class VolumePickerViewController: UIViewController {

    // MARK: - Callbacks

    /// Invoked whenever volume or fade-in flag changes. The caller keeps the
    /// alarm model in sync so the back-button pop is "auto-save".
    var onChange: ((Float, Bool) -> Void)?

    // MARK: - State

    private var volume: Float
    private var fadeIn: Bool

    /// 5%-step quantisation — matches the design-refresh spec. Slider value
    /// is rounded to the nearest multiple of `step` so the preview reads
    /// "65%" instead of "64.7%".
    private static let step: Float = 0.05

    // MARK: - UI

    private let previewCard = SPCard(tone: .surface, padding: AppSpacing.sp6)
    private let previewCaps: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.attributedText = NSAttributedString(
            string: "ГРОМКОСТЬ",
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: AppColors.fg3
            ]
        )
        return label
    }()
    private let previewValue: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = AppTypography.moneyXl
        label.textColor = AppColors.fg1
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        return label
    }()

    private let slider: UISlider = {
        let slider = UISlider()
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.minimumValue = 0
        slider.maximumValue = 1
        slider.minimumTrackTintColor = AppColors.money500
        slider.tintColor = AppColors.money500
        return slider
    }()

    private let fadeRowContainer = SPCard(tone: .surface, padding: AppSpacing.sp4)
    private let fadeSwitch = SPSwitch()

    private let stack: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = AppSpacing.sp5
        stack.alignment = .fill
        return stack
    }()

    // MARK: - Init

    /// - Parameters:
    ///   - volume: Initial volume in `0.0...1.0`.
    ///   - fadeIn: Initial fade-in flag.
    ///   - onChange: Callback fired on every slider / switch change with
    ///     `(volume, fadeIn)` — the caller persists.
    init(volume: Float, fadeIn: Bool, onChange: ((Float, Bool) -> Void)? = nil) {
        // Clamp the seed value so a corrupt persisted volume can't push the
        // slider out of bounds and crash on the first valueChanged event.
        self.volume = min(max(volume.isFinite ? volume : 1.0, 0), 1)
        self.fadeIn = fadeIn
        self.onChange = onChange
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Громкость"
        view.backgroundColor = AppColors.bg0
        setupUI()
        applyVolumeToUI()
        applyFadeToUI()
    }

    // MARK: - Setup

    private func setupUI() {
        view.addSubview(stack)
        configurePreviewCard()
        let sliderContainer = makeSliderContainer()
        configureFadeRow()
        stack.addArrangedSubview(previewCard)
        stack.addArrangedSubview(sliderContainer)
        stack.addArrangedSubview(fadeRowContainer)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: AppSpacing.sp5),
            stack.leadingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: AppSpacing.sp5
            ),
            stack.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -AppSpacing.sp5
            )
        ])
    }

    private func configurePreviewCard() {
        previewCard.translatesAutoresizingMaskIntoConstraints = false
        let previewStack = UIStackView(arrangedSubviews: [previewCaps, previewValue])
        previewStack.translatesAutoresizingMaskIntoConstraints = false
        previewStack.axis = .vertical
        previewStack.spacing = AppSpacing.sp2
        previewStack.alignment = .center
        previewCard.addSubview(previewStack)
        NSLayoutConstraint.activate([
            previewStack.leadingAnchor.constraint(equalTo: previewCard.layoutMarginsGuide.leadingAnchor),
            previewStack.trailingAnchor.constraint(equalTo: previewCard.layoutMarginsGuide.trailingAnchor),
            previewStack.topAnchor.constraint(equalTo: previewCard.layoutMarginsGuide.topAnchor),
            previewStack.bottomAnchor.constraint(equalTo: previewCard.layoutMarginsGuide.bottomAnchor)
        ])
    }

    /// Larger thumb so the control reads as a "fat dial" matching the SP
    /// design language. UIKit only exposes the thumb image — render a
    /// money-tinted disc into a programmatic image instead of shipping an
    /// asset.
    private func makeSliderContainer() -> UIView {
        slider.setThumbImage(Self.makeThumb(diameter: 28), for: .normal)
        slider.setThumbImage(Self.makeThumb(diameter: 30), for: .highlighted)
        slider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(slider)
        NSLayoutConstraint.activate([
            slider.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            slider.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            slider.topAnchor.constraint(equalTo: container.topAnchor, constant: AppSpacing.sp2),
            slider.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -AppSpacing.sp2),
            slider.heightAnchor.constraint(greaterThanOrEqualToConstant: 32)
        ])
        return container
    }

    private func configureFadeRow() {
        fadeRowContainer.translatesAutoresizingMaskIntoConstraints = false
        let fadeRow = SPRow(
            title: "Постепенно нарастает",
            subtitle: "За 30 секунд",
            trailing: fadeSwitch,
            divider: false
        )
        fadeRow.translatesAutoresizingMaskIntoConstraints = false
        fadeRowContainer.addSubview(fadeRow)
        NSLayoutConstraint.activate([
            fadeRow.leadingAnchor.constraint(equalTo: fadeRowContainer.layoutMarginsGuide.leadingAnchor),
            fadeRow.trailingAnchor.constraint(equalTo: fadeRowContainer.layoutMarginsGuide.trailingAnchor),
            fadeRow.topAnchor.constraint(equalTo: fadeRowContainer.layoutMarginsGuide.topAnchor),
            fadeRow.bottomAnchor.constraint(equalTo: fadeRowContainer.layoutMarginsGuide.bottomAnchor)
        ])
        fadeSwitch.addTarget(self, action: #selector(fadeToggled), for: .valueChanged)
    }

    // MARK: - State sync

    private func applyVolumeToUI() {
        slider.value = volume
        previewValue.text = "\(Int(round(volume * 100)))%"
    }

    private func applyFadeToUI() {
        fadeSwitch.isOn = fadeIn
    }

    // MARK: - Actions

    @objc
    private func sliderChanged() {
        // Quantise to 5% steps so the preview number doesn't flicker on
        // sub-percent jitter. Round-then-clamp keeps the ends snappy.
        let stepped = (slider.value / Self.step).rounded() * Self.step
        let clamped = min(max(stepped, 0), 1)
        if abs(clamped - volume) < .ulpOfOne { return }
        volume = clamped
        applyVolumeToUI()
        onChange?(volume, fadeIn)
    }

    @objc
    private func fadeToggled() {
        fadeIn = fadeSwitch.isOn
        onChange?(volume, fadeIn)
    }

    // MARK: - Thumb image

    /// Render a money-tinted circle into a UIImage for use as the slider
    /// thumb. Sizing the thumb via `setThumbImage` is the only supported
    /// path on `UISlider` — there's no `thumbDiameter` knob.
    private static func makeThumb(diameter: CGFloat) -> UIImage {
        let size = CGSize(width: diameter, height: diameter)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            // Soft ring shadow so the thumb lifts off the track in light mode.
            context.cgContext.setShadow(
                offset: CGSize(width: 0, height: 1),
                blur: 2,
                color: UIColor.black.withAlphaComponent(0.25).cgColor
            )
            AppColors.money500.setFill()
            UIBezierPath(ovalIn: rect).fill()
            // White inner dot so the thumb reads on dark + light alike.
            context.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
            UIColor.white.withAlphaComponent(0.35).setFill()
            let inner = rect.insetBy(dx: rect.width * 0.32, dy: rect.height * 0.32)
            UIBezierPath(ovalIn: inner).fill()
        }
    }
}
