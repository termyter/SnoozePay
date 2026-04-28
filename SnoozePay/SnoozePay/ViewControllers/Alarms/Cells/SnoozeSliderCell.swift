import UIKit

/// "Время откладывания" row: slider 1...15 minutes + live "{N} мин" label.
///
/// Replaces the previous `UIStepper`-based `SnoozeCell` (#143). The slider
/// snaps to integer minutes via `roundf` so the user never lands on noisy
/// fractional values, and the live label sits to the trailing side at a
/// fixed width so the slider's track doesn't reflow as the value changes.
final class SnoozeSliderCell: UITableViewCell {

    static let reuseID = "SnoozeSliderCell"

    /// Minimum minutes value exposed by the slider (matches PM spec).
    private static let minMinutes: Int = 1
    /// Maximum minutes value exposed by the slider (matches PM spec).
    private static let maxMinutes: Int = 15

    // MARK: - UI

    private let slider: UISlider = {
        let view = UISlider()
        view.minimumValue = Float(SnoozeSliderCell.minMinutes)
        view.maximumValue = Float(SnoozeSliderCell.maxMinutes)
        // Brand-tint the track to match the volume slider on the same screen
        // (#179) — the system blue clashes with the SP money palette.
        view.minimumTrackTintColor = AppColors.money500
        view.setThumbImage(SnoozeSliderCell.makeThumb(diameter: 28), for: .normal)
        view.setThumbImage(SnoozeSliderCell.makeThumb(diameter: 30), for: .highlighted)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let valueLabel: UILabel = {
        let label = UILabel()
        label.font = AppTypography.body
        label.textColor = AppColors.fg1
        label.textAlignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - Callbacks

    /// Fires whenever the slider settles on a new (integer) minute value
    /// inside the supported 1...15 range.
    var onValueChanged: ((Int) -> Void)?

    // MARK: - Init

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
        slider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupUI() {
        backgroundColor = AppColors.bg1
        selectionStyle = .none

        contentView.addSubview(slider)
        contentView.addSubview(valueLabel)

        NSLayoutConstraint.activate([
            slider.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: AppSpacing.lg),
            slider.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            slider.topAnchor.constraint(equalTo: contentView.topAnchor, constant: AppSpacing.md),
            slider.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -AppSpacing.md),

            valueLabel.leadingAnchor.constraint(equalTo: slider.trailingAnchor, constant: AppSpacing.md),
            valueLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -AppSpacing.lg),
            valueLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            // Reserve a fixed minimum so "1 мин" / "15 мин" don't reflow the
            // slider's effective track length as the user drags.
            valueLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 56)
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onValueChanged = nil
    }

    // MARK: - Configure

    /// Seed the slider with a stored value. Values outside the 1...15 range
    /// are clamped so a legacy alarm persisted with the old 30-minute upper
    /// bound still renders cleanly.
    func configure(minutes: Int) {
        let clamped = min(max(minutes, Self.minMinutes), Self.maxMinutes)
        slider.value = Float(clamped)
        valueLabel.text = "\(clamped) мин"
    }

    // MARK: - Actions

    @objc private func sliderChanged() {
        // Round to the nearest integer minute, clamp into the supported
        // range, and snap the slider thumb so the user feels discrete steps.
        let rounded = Int(roundf(slider.value))
        let clamped = min(max(rounded, Self.minMinutes), Self.maxMinutes)
        slider.value = Float(clamped)
        valueLabel.text = "\(clamped) мин"
        onValueChanged?(clamped)
    }

    // MARK: - Thumb image

    /// Render a money-tinted circle into a UIImage for use as the slider
    /// thumb. Sizing the thumb via `setThumbImage` is the only supported
    /// path on `UISlider` — there's no `thumbDiameter` knob. Mirrors the
    /// recipe in `VolumePickerViewController` so the two sliders that sit
    /// on the CreateAlarm screen render with visual parity (#179).
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
