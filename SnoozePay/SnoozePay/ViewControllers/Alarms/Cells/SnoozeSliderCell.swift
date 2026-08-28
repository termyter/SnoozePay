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

    /// In-card caps caption «Длительность откладывания» (SPMore2.jsx:268).
    /// Lives inside the card so the table no longer needs a section header (#278).
    private let captionLabel: UILabel = {
        let label = UILabel()
        label.attributedText = NSAttributedString(
            string: "Длительность откладывания".uppercased(),
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: AppColors.fg3
            ]
        )
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    /// Meta hint «На сколько минут отодвигается звонок» (SPMore2.jsx:269).
    private let hintLabel: UILabel = {
        let label = UILabel()
        label.text = "На сколько минут отодвигается звонок"
        label.font = AppTypography.meta
        label.textColor = AppColors.fg3
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let slider: UISlider = {
        let view = UISlider()
        view.minimumValue = Float(SnoozeSliderCell.minMinutes)
        view.maximumValue = Float(SnoozeSliderCell.maxMinutes)
        // V2: tint the track `warn500` so the snooze-duration slider reads
        // as "amber affordance" matching the JSX recipe in `SPScreensV2.jsx`
        // line 563.
        view.minimumTrackTintColor = AppColors.warn500
        view.setThumbImage(SnoozeSliderCell.makeThumb(diameter: 28), for: .normal)
        view.setThumbImage(SnoozeSliderCell.makeThumb(diameter: 30), for: .highlighted)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let valueLabel: UILabel = {
        let label = UILabel()
        // V2: mono `moneyMd` so the "{N} мин" reading column-aligns with the
        // penalty preset row's amount on the same screen.
        label.font = AppTypography.moneyMd
        label.textColor = AppColors.fg1
        label.textAlignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    /// Range bound labels under the track — «1 мин» / «15 мин» (SPScreensV2.jsx
    /// :567-570, `fg4` meta) so the slider's extents are legible at a glance.
    private static func makeBoundLabel(_ text: String, alignment: NSTextAlignment) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = AppTypography.meta
        label.textColor = AppColors.fg4
        label.textAlignment = alignment
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private lazy var minBoundLabel = Self.makeBoundLabel("\(Self.minMinutes) мин", alignment: .left)
    private lazy var maxBoundLabel = Self.makeBoundLabel("\(Self.maxMinutes) мин", alignment: .right)

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

        contentView.addSubview(captionLabel)
        contentView.addSubview(hintLabel)
        contentView.addSubview(slider)
        contentView.addSubview(valueLabel)
        contentView.addSubview(minBoundLabel)
        contentView.addSubview(maxBoundLabel)

        NSLayoutConstraint.activate([
            captionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: AppSpacing.lg),
            captionLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: AppSpacing.sm),

            hintLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: AppSpacing.lg),
            hintLabel.topAnchor.constraint(equalTo: captionLabel.bottomAnchor, constant: 2),
            hintLabel.trailingAnchor.constraint(lessThanOrEqualTo: valueLabel.leadingAnchor, constant: -AppSpacing.sm),

            valueLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -AppSpacing.lg),
            valueLabel.firstBaselineAnchor.constraint(equalTo: captionLabel.firstBaselineAnchor),
            // Reserve a fixed minimum so "1 мин" / "15 мин" don't reflow.
            valueLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 56),

            slider.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: AppSpacing.lg),
            slider.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -AppSpacing.lg),
            slider.topAnchor.constraint(equalTo: hintLabel.bottomAnchor, constant: AppSpacing.sm),

            // Range bounds under the track (space-between, marginTop 8 in JSX).
            minBoundLabel.leadingAnchor.constraint(equalTo: slider.leadingAnchor),
            minBoundLabel.topAnchor.constraint(equalTo: slider.bottomAnchor, constant: AppSpacing.sm),
            maxBoundLabel.trailingAnchor.constraint(equalTo: slider.trailingAnchor),
            maxBoundLabel.firstBaselineAnchor.constraint(equalTo: minBoundLabel.firstBaselineAnchor),
            minBoundLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -AppSpacing.md)
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
        valueLabel.attributedText = Self.valueText(clamped)
    }

    // MARK: - Actions

    @objc private func sliderChanged() {
        // Round to the nearest integer minute, clamp into the supported
        // range, and snap the slider thumb so the user feels discrete steps.
        let rounded = Int(roundf(slider.value))
        let clamped = min(max(rounded, Self.minMinutes), Self.maxMinutes)
        slider.value = Float(clamped)
        valueLabel.attributedText = Self.valueText(clamped)
        onValueChanged?(clamped)
    }

    /// "{N} мин" with the «мин» suffix dimmed to `fg3` per the V2 slider
    /// recipe (SPScreensV2.jsx:733-751) so the number reads as the headline.
    private static func valueText(_ minutes: Int) -> NSAttributedString {
        let text = NSMutableAttributedString(
            string: "\(minutes)",
            attributes: [
                .font: AppTypography.moneyMd,
                .foregroundColor: AppColors.fg1
            ]
        )
        text.append(NSAttributedString(
            string: " мин",
            attributes: [
                .font: AppTypography.h4,
                .foregroundColor: AppColors.fg3
            ]
        ))
        return text
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
