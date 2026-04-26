import UIKit

/// Horizontal Пн-Вс day toggle row. Each weekday is rendered as a square button
/// that toggles its selection state independently. The cell owns its buttons
/// internally; the controller only supplies the current selection set.
final class DayPickerCell: UITableViewCell {

    static let reuseID = "DayPickerCell"

    private static let dayNames = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]

    // MARK: - UI

    private let stackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 4
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
        backgroundColor = .secondarySystemBackground

        for index in 0..<Self.dayNames.count {
            let button = UIButton(type: .system)
            button.setTitle(Self.dayNames[index], for: .normal)
            button.tag = index
            button.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .medium)
            button.layer.cornerRadius = 8
            button.layer.masksToBounds = true
            button.addTarget(self, action: #selector(dayTapped(_:)), for: .touchUpInside)
            dayButtons.append(button)
            stackView.addArrangedSubview(button)
        }

        contentView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: AppSpacing.lg),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -AppSpacing.lg),
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: AppSpacing.sm),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -AppSpacing.sm),
            stackView.heightAnchor.constraint(equalToConstant: 44)
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
            let isSelected = selected.contains(index)
            button.backgroundColor = isSelected ? AppColors.accentBlue : .tertiarySystemBackground
            button.setTitleColor(isSelected ? .white : .label, for: .normal)
        }
    }

    // MARK: - Actions

    @objc private func dayTapped(_ sender: UIButton) {
        onDayToggled?(sender.tag)
    }
}
