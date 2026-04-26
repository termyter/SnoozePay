import UIKit

/// Penalty-amount slider with a live value label rounded to the nearest 10.
final class PenaltyCell: UITableViewCell {

    static let reuseID = "PenaltyCell"

    // MARK: - UI

    private let slider: UISlider = {
        let view = UISlider()
        view.minimumValue = 10
        view.maximumValue = 1000
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let valueLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 17)
        label.textColor = AppColors.accentOrange
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - Callbacks

    /// Fires whenever the slider settles on a new (10-rounded) value.
    var onValueChanged: ((Double) -> Void)?

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
        backgroundColor = .secondarySystemBackground
        selectionStyle = .none

        let stack = UIStackView(arrangedSubviews: [slider, valueLabel])
        stack.axis = .horizontal
        stack.spacing = AppSpacing.md
        stack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: AppSpacing.lg),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -AppSpacing.lg),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: AppSpacing.md),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -AppSpacing.md)
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onValueChanged = nil
    }

    // MARK: - Configure

    func configure(amount: Double) {
        slider.value = Float(amount)
        valueLabel.text = "\(Int(amount)) ₽"
    }

    // MARK: - Actions

    @objc private func sliderChanged() {
        // Round to nearest 10 so the user never lands on noisy values like 137.
        let rounded = (slider.value / 10).rounded() * 10
        slider.value = rounded
        valueLabel.text = "\(Int(rounded)) ₽"
        onValueChanged?(Double(rounded))
    }
}
