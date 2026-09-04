import UIKit

/// V2 horizontal Пн-Вс day toggle row. Each weekday button is a 36×36 round
/// chip — selected = `money500` flat fill + `fgOnMoney` text (the JSX uses
/// the money gradient; we collapse to the dominant stop because `UIButton`
/// doesn't render a gradient inline). Unselected = `whiteOverlay06` chip with
/// `fg3` text. Matches `SPScreensV2.jsx` lines 528-541.
final class DayPickerCell: UITableViewCell {

    static let reuseID = "DayPickerCell"

    // Weekday names are calendar data, not copy: they come from the locale
    // via `WeekdayNames` rather than from `Localizable.xcstrings` (#569).
    private static let dayNames = WeekdayNames.short
    private static let buttonDiameter: CGFloat = 36

    // MARK: - UI

    private let stackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        // `.equalSpacing`, not `.fillEqually`: the latter stretched each
        // chip to its slot width (~44pt) while the height stayed 36, so a
        // circle drawn at `diameter / 2` rendered as an oval. Now the chip
        // keeps its 36×36 box and the leftover width becomes gap.
        stack.distribution = .equalSpacing
        stack.spacing = AppSpacing.sp2
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private var dayButtons: [UIButton] = []

    // MARK: - Callbacks

    /// Notifies the controller that the user tapped a weekday (0...6).
    /// The controller mutates the view-model and calls `configure(...)`
    /// again to repaint the buttons.
    var onDayToggled: ((Int) -> Void)?

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

        for index in 0..<Self.dayNames.count {
            let button = UIButton(type: .system)
            button.setTitle(Self.dayNames[index], for: .normal)
            button.tag = index
            button.titleLabel?.font = AppTypography.buttonSm
            button.layer.cornerRadius = Self.buttonDiameter / 2
            button.layer.masksToBounds = true
            button.addTarget(self, action: #selector(dayTapped(_:)), for: .touchUpInside)
            button.heightAnchor.constraint(equalToConstant: Self.buttonDiameter).isActive = true
            button.widthAnchor.constraint(equalToConstant: Self.buttonDiameter).isActive = true
            dayButtons.append(button)
            stackView.addArrangedSubview(button)
        }

        contentView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: AppSpacing.cardHorizontalPadding
            ),
            stackView.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -AppSpacing.cardHorizontalPadding
            ),
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: AppSpacing.sp2),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -AppSpacing.sp2)
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onDayToggled = nil
    }

    // MARK: - Configure

    func configure(selectedDays: [Int]) {
        let selected = Set(selectedDays)
        for (index, button) in dayButtons.enumerated() {
            applyStyle(button, isSelected: selected.contains(index))
        }
    }

    /// V2: selected → `money500` fill + `fgOnMoney` text; unselected →
    /// `whiteOverlay06` chip + `fg3` text. No border in either state.
    private func applyStyle(_ button: UIButton, isSelected: Bool) {
        if isSelected {
            button.backgroundColor = AppColors.money500
            button.setTitleColor(AppColors.fgOnMoney, for: .normal)
        } else {
            button.backgroundColor = AppColors.whiteOverlay06
            button.setTitleColor(AppColors.fg3, for: .normal)
        }
        button.layer.borderWidth = 0
        button.accessibilityValue = Localized.text(
            isSelected ? "create_alarm.accessibility.selected" : "create_alarm.accessibility.not_selected"
        )
    }

    // MARK: - Actions

    @objc private func dayTapped(_ sender: UIButton) {
        UISelectionFeedbackGenerator().selectionChanged()
        onDayToggled?(sender.tag)
    }
}
