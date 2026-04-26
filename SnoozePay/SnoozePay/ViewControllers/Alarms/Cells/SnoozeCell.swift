import UIKit

/// "Откладывать на" row: title + minutes-detail + stepper accessory.
///
/// Uses the built-in `.value1` style so the "X мин" detail text sits between
/// the title and the stepper without needing a custom stack — the stepper
/// + label combo did not produce a sensible intrinsic size when wrapped in
/// a `UIStackView` (clipped the value label).
final class SnoozeCell: UITableViewCell {

    static let reuseID = "SnoozeCell"

    // MARK: - UI

    private let stepper: UIStepper = {
        let view = UIStepper()
        view.minimumValue = 1
        view.maximumValue = 30
        view.stepValue = 1
        return view
    }()

    // MARK: - Callbacks

    var onValueChanged: ((Int) -> Void)?

    // MARK: - Init

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        // Force `.value1` regardless of caller — this style is the whole point
        // of the cell and keeps the detail label correctly positioned.
        super.init(style: .value1, reuseIdentifier: reuseIdentifier)
        textLabel?.text = "Откладывать на"
        detailTextLabel?.textColor = .label
        backgroundColor = .secondarySystemBackground
        selectionStyle = .none
        accessoryView = stepper
        stepper.addTarget(self, action: #selector(stepperChanged), for: .valueChanged)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onValueChanged = nil
    }

    // MARK: - Configure

    func configure(minutes: Int) {
        stepper.value = Double(minutes)
        detailTextLabel?.text = "\(minutes) мин"
    }

    // MARK: - Actions

    @objc private func stepperChanged() {
        let value = Int(stepper.value)
        // Update the visible detail label in place so the stepper does not
        // briefly snap before the controller's `reload` cycle catches up.
        detailTextLabel?.text = "\(value) мин"
        onValueChanged?(value)
    }
}
