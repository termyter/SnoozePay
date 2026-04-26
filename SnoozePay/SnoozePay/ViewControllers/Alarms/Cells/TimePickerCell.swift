import UIKit

/// Wheel-style time picker cell. Owns its own UIDatePicker so the control is
/// never shared between rows — eliminating the stale-constraint crash that
/// plagued the previous shared-property implementation.
final class TimePickerCell: UITableViewCell {

    static let reuseID = "TimePickerCell"

    // MARK: - UI

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
        backgroundColor = .secondarySystemBackground
        contentView.addSubview(picker)
        NSLayoutConstraint.activate([
            picker.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            picker.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            picker.topAnchor.constraint(equalTo: contentView.topAnchor),
            picker.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onTimeChanged = nil
    }

    // MARK: - Configure

    func configure(time: Date) {
        picker.date = time
    }

    // MARK: - Actions

    @objc private func pickerChanged() {
        onTimeChanged?(picker.date)
    }
}
