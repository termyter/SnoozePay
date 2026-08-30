import UIKit

/// Wheel-style time picker cell. Owns its own UIDatePicker so the control is
/// never shared between rows — eliminating the stale-constraint crash that
/// plagued the previous shared-property implementation.
///
/// V2 (#284): the stock wheels are kept as the input mechanism (good UX on
/// iOS), but the cell now leads with the branded readout from the artboard
/// (`SPScreensV2.jsx:520-527`): a caps «Подъём» header above a clock-XL mono
/// readout (`HH` · `:` · `mm`) that mirrors the current wheel selection. The
/// `:` separator is dimmed (`fg4`) and the digits use `fg1`, matching the
/// design's tabular-numeral / tight-tracking look.
final class TimePickerCell: UITableViewCell {

    static let reuseID = "TimePickerCell"

    /// Fixed height the host controller reserves for this row. The clock-XL
    /// readout (96pt ultralight) plus the caps header and the wheels picker
    /// need more vertical room than the old wheels-only 200pt — exposed here so
    /// `heightForRowAt` reads from one source of truth.
    static let rowHeight: CGFloat = 320

    // MARK: - UI

    /// «Подъём» — caps header above the readout (`sp-caps`, `fg3`).
    private let headerLabel: UILabel = {
        let label = UILabel()
        label.text = Localized.text("create_alarm.wake_up").uppercased()
        label.font = AppTypography.caps
        label.textColor = AppColors.fg3
        label.textAlignment = .center
        label.attributedText = NSAttributedString(
            string: label.text ?? "",
            attributes: [.kern: AppTypography.capsKerning]
        )
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    /// Clock-XL mono readout (`HH:mm`) reflecting the live wheel selection.
    /// A single attributed string keeps the digits / dimmed separator aligned
    /// on the baseline without three separate labels.
    private let readoutLabel: UILabel = {
        let label = UILabel()
        label.font = AppTypography.clockXl
        label.textColor = AppColors.fg1
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let picker: UIDatePicker = {
        let view = UIDatePicker()
        view.datePickerMode = .time
        view.preferredDatePickerStyle = .wheels
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    // MARK: - Callbacks

    /// Forwards the picker's new date to the controller. Cleared in
    /// `prepareForReuse` so a recycled cell never fires the wrong alarm's
    /// time before the next `configure(...)`.
    var onTimeChanged: ((Date) -> Void)?

    // MARK: - Init

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
        picker.addTarget(self, action: #selector(pickerChanged), for: .valueChanged)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupUI() {
        selectionStyle = .none
        // `bg1`, the same card token every other row of the form sets. The
        // cell's own fill is overwritten with `.clear` by `styleAsCardRow` in
        // `willDisplay`, so what actually renders is `CardRowBackgroundView`'s
        // `bg1` — this line only has to agree with it before the row is shown.
        backgroundColor = AppColors.bg1

        let stack = UIStackView(arrangedSubviews: [headerLabel, readoutLabel, picker])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = AppSpacing.sp2
        stack.setCustomSpacing(AppSpacing.sp4, after: readoutLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: AppSpacing.sp5),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -AppSpacing.sp4),
            stack.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: AppSpacing.cardHorizontalPadding
            ),
            stack.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -AppSpacing.cardHorizontalPadding
            ),
            // Wheels span the full readable width so the picker doesn't shrink
            // to the readout's intrinsic size inside the centred stack.
            picker.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            picker.trailingAnchor.constraint(equalTo: stack.trailingAnchor)
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onTimeChanged = nil
    }

    // MARK: - Configure

    func configure(time: Date) {
        picker.date = time
        updateReadout(for: time)
    }

    // MARK: - Readout

    /// Renders the picked time with `fg1` digits and a dimmed (`fg4`) `:`
    /// separator, mirroring the artboard's three-span layout in one attributed
    /// string.
    ///
    /// The readout follows the reader's hour cycle (#628) — it sits directly
    /// above a `UIDatePicker`, which has always rendered its wheels in the
    /// device's cycle, so the `en_US_POSIX` pin here used to put "19:00" over a
    /// wheel reading "7:00 PM". The separator lookup still holds on a 12-hour
    /// string ("7:00 PM" has exactly one colon).
    private func updateReadout(for date: Date) {
        let text = WallClockFormatter.string(from: date, style: .padded)
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: AppTypography.clockXl,
                .foregroundColor: AppColors.fg1,
                .kern: -3.0
            ]
        )
        if let colonRange = text.range(of: ":") {
            let nsRange = NSRange(colonRange, in: text)
            attributed.addAttribute(.foregroundColor, value: AppColors.fg4, range: nsRange)
            // Drop the negative tracking on the separator so it sits centred
            // between the digit pairs instead of hugging the minutes.
            attributed.addAttribute(.kern, value: 0.0, range: nsRange)
        }
        readoutLabel.attributedText = attributed
    }

    // MARK: - Actions

    @objc private func pickerChanged() {
        updateReadout(for: picker.date)
        onTimeChanged?(picker.date)
    }
}
