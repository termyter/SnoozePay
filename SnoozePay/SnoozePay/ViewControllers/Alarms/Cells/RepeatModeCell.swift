import UIKit

/// V2 repeat-mode selector under the day chips (#229): caps caption
/// `ПОВТОР`, a centered two-segment pill **Никогда / Еженедельно**, and a
/// one-line hint explaining the selected behaviour. Matches the
/// `RepeatSegmented` component in `SPScreensV2.jsx` — the active segment
/// uses the money treatment, the inactive one stays transparent on a
/// `whiteOverlay06` capsule track. Like `DayPickerCell`, the active fill
/// collapses the JSX money gradient to the dominant `money500` stop because
/// `UIButton` doesn't render a gradient inline.
final class RepeatModeCell: UITableViewCell {

    static let reuseID = "RepeatModeCell"

    private static let segmentHeight: CGFloat = 36
    private static let trackPadding: CGFloat = 4

    /// Ordered segments. Index == button tag.
    ///
    /// Computed rather than stored: a `static let` would freeze the labels at
    /// first access, and a missing catalogue key would then hide behind
    /// whichever test happened to touch the cell first (see `Plural`).
    private static var modes: [(mode: AlarmRepeatMode, label: String)] {
        [
            (.never, Localized.text("create_alarm.repeat.never")),
            (.weekly, Localized.text("create_alarm.repeat.weekly"))
        ]
    }

    // MARK: - Callbacks

    /// Notifies the controller that the user picked a mode. The controller
    /// mutates the view-model and calls `configure(...)` again to repaint
    /// the segments + hint.
    var onModeChanged: ((AlarmRepeatMode) -> Void)?

    // MARK: - UI

    private let captionLabel: UILabel = {
        let label = UILabel()
        label.attributedText = NSAttributedString(
            string: Localized.text("create_alarm.repeat.caps"),
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: AppColors.fg3
            ]
        )
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let track: UIView = {
        let view = UIView()
        view.backgroundColor = AppColors.whiteOverlay06
        view.layer.cornerRadius = (RepeatModeCell.segmentHeight + RepeatModeCell.trackPadding * 2) / 2
        view.layer.masksToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let segmentStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = RepeatModeCell.trackPadding
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let hintLabel: UILabel = {
        let label = UILabel()
        label.font = AppTypography.meta
        label.textColor = AppColors.fg3
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private var segmentButtons: [UIButton] = []

    // MARK: - Init

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupUI() {
        selectionStyle = .none
        backgroundColor = AppColors.bg1

        for (index, option) in Self.modes.enumerated() {
            var config = UIButton.Configuration.plain()
            config.contentInsets = NSDirectionalEdgeInsets(
                top: 0, leading: AppSpacing.sp4 + 2, bottom: 0, trailing: AppSpacing.sp4 + 2
            )
            let button = UIButton(configuration: config)
            button.tag = index
            button.layer.cornerRadius = Self.segmentHeight / 2
            button.layer.masksToBounds = true
            button.accessibilityLabel = option.label
            button.addTarget(self, action: #selector(segmentTapped(_:)), for: .touchUpInside)
            button.heightAnchor.constraint(equalToConstant: Self.segmentHeight).isActive = true
            segmentButtons.append(button)
            segmentStack.addArrangedSubview(button)
        }

        track.addSubview(segmentStack)
        contentView.addSubview(captionLabel)
        contentView.addSubview(track)
        contentView.addSubview(hintLabel)

        NSLayoutConstraint.activate([
            captionLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: AppSpacing.sp2),
            captionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: AppSpacing.sp5),
            captionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -AppSpacing.sp5),

            track.topAnchor.constraint(equalTo: captionLabel.bottomAnchor, constant: AppSpacing.sp2),
            track.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            track.leadingAnchor.constraint(
                greaterThanOrEqualTo: contentView.leadingAnchor, constant: AppSpacing.sp5
            ),

            segmentStack.topAnchor.constraint(equalTo: track.topAnchor, constant: Self.trackPadding),
            segmentStack.bottomAnchor.constraint(equalTo: track.bottomAnchor, constant: -Self.trackPadding),
            segmentStack.leadingAnchor.constraint(equalTo: track.leadingAnchor, constant: Self.trackPadding),
            segmentStack.trailingAnchor.constraint(equalTo: track.trailingAnchor, constant: -Self.trackPadding),

            hintLabel.topAnchor.constraint(equalTo: track.bottomAnchor, constant: AppSpacing.sp2),
            hintLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            hintLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 280),
            hintLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -AppSpacing.sp3)
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onModeChanged = nil
    }

    // MARK: - Configure

    func configure(mode: AlarmRepeatMode, hint: String) {
        for (index, button) in segmentButtons.enumerated() {
            applyStyle(button, option: Self.modes[index], isSelected: Self.modes[index].mode == mode)
        }
        hintLabel.text = hint
    }

    /// Active → `money500` fill + `fgOnMoney` text; inactive → transparent
    /// segment on the capsule track + `fg2` text (V2 RepeatSegmented).
    private func applyStyle(
        _ button: UIButton,
        option: (mode: AlarmRepeatMode, label: String),
        isSelected: Bool
    ) {
        button.backgroundColor = isSelected ? AppColors.money500 : .clear
        var title = AttributedString(option.label)
        title.font = AppTypography.buttonSm
        title.foregroundColor = isSelected ? AppColors.fgOnMoney : AppColors.fg2
        button.configuration?.attributedTitle = title
        button.accessibilityValue = Localized.text(
            isSelected ? "create_alarm.accessibility.selected" : "create_alarm.accessibility.not_selected"
        )
    }

    // MARK: - Actions

    @objc private func segmentTapped(_ sender: UIButton) {
        guard let option = Self.modes[safe: sender.tag] else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        onModeChanged?(option.mode)
    }
}

// MARK: - Safe array subscript
private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
