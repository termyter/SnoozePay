import UIKit

/// Table view cell for displaying a single alarm in the list.
final class AlarmCell: UITableViewCell {

    static let reuseID = "AlarmCell"

    // MARK: - UI Elements

    private let timeLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 36, weight: .thin)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 13, weight: .regular)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 13, weight: .regular)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    let toggleSwitch: UISwitch = {
        let sw = UISwitch()
        sw.onTintColor = AppColors.accentGreen
        sw.translatesAutoresizingMaskIntoConstraints = false
        return sw
    }()

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
        backgroundColor = AppColors.surface
        selectionStyle = .none

        let textStack = UIStackView(arrangedSubviews: [timeLabel, subtitleLabel, nameLabel])
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(textStack)
        contentView.addSubview(toggleSwitch)

        NSLayoutConstraint.activate([
            textStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: AppSpacing.lg),
            textStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: toggleSwitch.leadingAnchor, constant: -AppSpacing.md),

            toggleSwitch.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -AppSpacing.lg),
            toggleSwitch.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 80)
        ])
    }

    // MARK: - Configure

    func configure(time: String, subtitle: String, name: String, enabled: Bool) {
        timeLabel.text = time
        subtitleLabel.text = subtitle
        nameLabel.text = name
        toggleSwitch.isOn = enabled

        // Dim text when disabled
        timeLabel.alpha = enabled ? 1.0 : 0.4
        subtitleLabel.alpha = enabled ? 1.0 : 0.4
        nameLabel.alpha = enabled ? 1.0 : 0.4
    }
}
