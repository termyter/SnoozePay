import UIKit

/// Horizontal Пн-Вс day toggle row. Each weekday is rendered as a square button
/// that toggles its selection state independently. The cell owns its buttons
/// internally; the controller only supplies the current selection set.
///
/// The buttons live inside a card-style container (rounded surface + hairline
/// border) so the row reads as one grouped control instead of seven loose
/// pills floating against the table background.
final class DayPickerCell: UITableViewCell {

    static let reuseID = "DayPickerCell"

    private static let dayNames = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
    private static let buttonHeight: CGFloat = 40

    // MARK: - UI

    private let cardView: UIView = {
        let view = UIView()
        view.backgroundColor = AppColors.surface
        view.layer.cornerRadius = AppRadius.md
        view.layer.borderWidth = 0.5
        view.layer.borderColor = AppColors.separator.cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let stackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = AppSpacing.xs
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private var dayButtons: [DayButton] = []

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
        backgroundColor = .secondarySystemBackground

        for index in 0..<Self.dayNames.count {
            let button = DayButton(type: .custom)
            button.setTitle(Self.dayNames[index], for: .normal)
            button.tag = index
            button.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
            button.layer.cornerRadius = AppRadius.sm
            button.layer.masksToBounds = true
            button.addTarget(self, action: #selector(dayTapped(_:)), for: .touchUpInside)
            dayButtons.append(button)
            stackView.addArrangedSubview(button)
        }

        contentView.addSubview(cardView)
        cardView.addSubview(stackView)

        NSLayoutConstraint.activate([
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: AppSpacing.lg),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -AppSpacing.lg),
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: AppSpacing.sm),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -AppSpacing.sm),

            stackView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: AppSpacing.sm),
            stackView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -AppSpacing.sm),
            stackView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: AppSpacing.sm),
            stackView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -AppSpacing.sm),
            stackView.heightAnchor.constraint(equalToConstant: Self.buttonHeight)
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onDayToggled = nil
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        // CGColor does not auto-update on appearance changes — refresh manually
        // so the hairline border stays visible in both light and dark modes.
        cardView.layer.borderColor = AppColors.separator.cgColor
    }

    // MARK: - Configure

    func configure(selectedDays: [Int]) {
        let selected = Set(selectedDays)
        for (index, button) in dayButtons.enumerated() {
            button.applySelected(selected.contains(index))
        }
    }

    // MARK: - Actions

    @objc private func dayTapped(_ sender: UIButton) {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        onDayToggled?(sender.tag)
    }
}

// MARK: - DayButton

/// Custom button that paints its own selected/unselected/pressed visuals so the
/// state is unambiguous (tinted fill for selected, neutral for unselected, dim
/// overlay while pressed). Using a subclass keeps the highlight behaviour out
/// of the cell and survives reuse.
private final class DayButton: UIButton {

    private var isOn: Bool = false

    override var isHighlighted: Bool {
        didSet { updateAppearance() }
    }

    func applySelected(_ selected: Bool) {
        isOn = selected
        updateAppearance()
    }

    private func updateAppearance() {
        let baseBackground: UIColor = isOn ? AppColors.accentBlue : AppColors.surface2
        let baseTitle: UIColor = isOn ? .white : AppColors.textPrimary

        if isHighlighted {
            backgroundColor = baseBackground.withAlphaComponent(0.7)
        } else {
            backgroundColor = baseBackground
        }
        setTitleColor(baseTitle, for: .normal)
    }
}
