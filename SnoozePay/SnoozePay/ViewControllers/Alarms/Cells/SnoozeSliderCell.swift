import UIKit

/// «Время откладывания» row: slider 1...15 minutes + live «{N} мин» label.
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
            string: Localized.text("create_alarm.snooze.caps").uppercased(),
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
        label.text = Localized.text("create_alarm.snooze.hint")
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
        // V2: tint the track amber so the snooze-duration slider reads as
        // "amber affordance" matching the JSX recipe in `SPScreensV2.jsx`
        // line 563.
        //
        // `warnFill500`, not `warn500` (#520). The ink tone measured 1.00:1
        // against the `money500` thumb in light — isoluminant, so the filled
        // and unfilled halves were told apart by hue alone and the control read
        // as one brown smudge. The fill tone measures 3.26:1 there.
        view.minimumTrackTintColor = AppColors.warnFill500
        // The unfilled remainder is `rgba(255,255,255,.10)` in the same JSX
        // gradient. UIKit's default maximum track is a fixed system grey that
        // neither theme asked for — on the light card it is a near-invisible
        // #E5E5EA on #FFFFFF. `whiteOverlay12` is the token for that literal
        // and darkens instead of lightening on the light theme.
        view.maximumTrackTintColor = AppColors.whiteOverlay12
        // Thumb images are installed in `init` (and re-installed on theme
        // flips) — a bitmap cannot resolve a dynamic colour on its own.
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let valueLabel: UILabel = {
        let label = UILabel()
        // V2: mono `moneyMd` so the «{N} мин» reading column-aligns with the
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

    private lazy var minBoundLabel = Self.makeBoundLabel(
        Localized.format("create_alarm.snooze.minutes", Self.minMinutes), alignment: .left
    )
    private lazy var maxBoundLabel = Self.makeBoundLabel(
        Localized.format("create_alarm.snooze.minutes", Self.maxMinutes), alignment: .right
    )

    // MARK: - Callbacks

    /// Fires whenever the slider settles on a new (integer) minute value
    /// inside the supported 1...15 range.
    var onValueChanged: ((Int) -> Void)?

    // MARK: - Init

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
        slider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
        // The thumb is a rendered bitmap, so it can't re-resolve its own
        // dynamic colours — re-render it whenever the theme flips.
        SPSliderThumb.install(on: slider, trait: traitCollection)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (cell: SnoozeSliderCell, _) in
            SPSliderThumb.install(on: cell.slider, trait: cell.traitCollection)
        }
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
            captionLabel.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: AppSpacing.cardHorizontalPadding
            ),
            captionLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: AppSpacing.sm),

            hintLabel.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: AppSpacing.cardHorizontalPadding
            ),
            hintLabel.topAnchor.constraint(equalTo: captionLabel.bottomAnchor, constant: 2),
            hintLabel.trailingAnchor.constraint(lessThanOrEqualTo: valueLabel.leadingAnchor, constant: -AppSpacing.sm),

            valueLabel.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -AppSpacing.cardHorizontalPadding
            ),
            valueLabel.firstBaselineAnchor.constraint(equalTo: captionLabel.firstBaselineAnchor),
            // Reserve a fixed minimum so «1 мин» / «15 мин» don't reflow.
            valueLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 56),

            slider.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: AppSpacing.cardHorizontalPadding
            ),
            slider.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -AppSpacing.cardHorizontalPadding
            ),
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

    /// «{N} мин» with the unit dimmed to `fg3` per the V2 slider recipe
    /// (SPScreensV2.jsx:733-751) so the number reads as the headline.
    ///
    /// The whole phrase is one catalogue string with the number substituted
    /// into it, rather than the two being concatenated here: a language that
    /// puts its unit first would otherwise be unable to say so. That argument
    /// is not this method's own — it belongs to
    /// ``Localized/attributed(_:attributes:replacing:specifier:)``, which is
    /// where every styled substitution in the app now goes.
    ///
    /// Until #722 this method made the same argument in its own words and its
    /// own way: render the phrase through ``Localized/format(_:_:)``, then
    /// find the number again with `range(of:)` and restyle it in place. Two
    /// mechanisms for one job, neither citing the other. The one that survived
    /// is the one that can also place an insertion whose own attributes are
    /// non-uniform, and that cannot restyle the wrong occurrence.
    ///
    /// `specifier` is `%lld` because the entry reads «%lld мин» — it was
    /// written to be consumed by ``Localized/format(_:_:)``, which hands the
    /// template to `String(format:)` with an `Int`, and that is the spelling
    /// that path wants. Not because the spelling predates the restyling: this
    /// reading has been styled apart since #278 (2026-06-12) — #220 had only
    /// set the whole label to `moneyMd` a month earlier — two and a half
    /// months before #612 (2026-08-30) moved the phrase into the catalogue,
    /// and that entry's own comment already says «the call site dims
    /// everything but the number». Respelling it `%@` now would churn the
    /// catalogue and re-open the entry for translation, which is what the
    /// `specifier` parameter exists to avoid. The number is rendered through
    /// the same locale-aware path it had while the whole phrase went through
    /// `String(format:locale:)`.
    ///
    /// Internal rather than private so `AttributedSubstitutionTests` can read
    /// the return value directly. Through `valueLabel.attributedText` the two
    /// expectations that matter most — `moneyMd` and `fg1` on the digit — are
    /// also the label's own defaults (see `valueLabel` above), so a mutation
    /// that inserts the number *without* attributes could come back looking
    /// correct. Reading what this method returns removes the label from the
    /// oracle; that the cell then renders it is pinned separately by
    /// `AlarmEditorCopyTests.testSnoozeSliderReadingKeepsItsNumberInTheHeadlineFace`.
    static func valueText(_ minutes: Int) -> NSAttributedString {
        Localized.attributed(
            "create_alarm.snooze.minutes",
            attributes: [
                .font: AppTypography.h4,
                .foregroundColor: AppColors.fg3
            ],
            replacing: NSAttributedString(
                string: String(format: "%lld", locale: AppLocale.display, arguments: [minutes]),
                attributes: [
                    .font: AppTypography.moneyMd,
                    .foregroundColor: AppColors.fg1
                ]
            ),
            specifier: "%lld"
        )
    }
}

// The thumb bitmap used to be rendered by a private `makeThumb` here, byte
// for byte identical to the one in `VolumePickerViewController` (#179). Both
// now call the shared, trait-aware `SPSliderThumb` so the two sliders on this
// screen cannot drift apart and neither freezes its theme (#492).
