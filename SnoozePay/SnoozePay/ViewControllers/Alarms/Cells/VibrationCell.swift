import UIKit

/// Toggle row for the "Вибрация" setting.
final class VibrationCell: UITableViewCell {

    static let reuseID = "VibrationCell"

    // MARK: - UI

    private let toggle: UISwitch = {
        let view = UISwitch()
        view.onTintColor = AppColors.accentGreen
        return view
    }()

    // MARK: - Callbacks

    var onToggled: ((Bool) -> Void)?

    // MARK: - Init

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        textLabel?.text = "Вибрация"
        backgroundColor = .secondarySystemBackground
        selectionStyle = .none
        accessoryView = toggle
        toggle.addTarget(self, action: #selector(toggled), for: .valueChanged)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onToggled = nil
    }

    // MARK: - Configure

    func configure(isOn: Bool) {
        toggle.isOn = isOn
    }

    // MARK: - Actions

    @objc private func toggled() {
        onToggled?(toggle.isOn)
    }
}
