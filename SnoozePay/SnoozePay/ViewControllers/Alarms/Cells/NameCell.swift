import UIKit

/// Single-line text input cell for the alarm's display name.
///
/// Refresh per #143/#231: iOS Reminders–style large placeholder "Название"
/// with no inline header, and exposes `beginEditing()` so the host
/// controller can auto-focus on appear in create-mode.
final class NameCell: UITableViewCell {

    static let reuseID = "NameCell"

    // MARK: - UI

    private let textField: UITextField = {
        let field = UITextField()
        field.font = AppTypography.h3
        field.textColor = AppColors.fg1
        field.translatesAutoresizingMaskIntoConstraints = false
        // Large attributed placeholder ("Название", #231) tinted with the
        // disabled foreground role so the field still reads as empty without
        // a label.
        field.attributedPlaceholder = NSAttributedString(
            string: "Название",
            attributes: [
                .font: AppTypography.h3,
                .foregroundColor: AppColors.fg4
            ]
        )
        field.returnKeyType = .done
        field.clearButtonMode = .whileEditing
        field.accessibilityIdentifier = "createAlarm.nameField"
        return field
    }()

    // MARK: - Callbacks

    /// Fires on every keystroke so the view-model stays in sync without
    /// having to read the field at save time.
    var onNameChanged: ((String) -> Void)?

    // MARK: - Init

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
        textField.addTarget(self, action: #selector(textChanged), for: .editingChanged)
        textField.addTarget(self, action: #selector(returnTapped), for: .editingDidEndOnExit)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupUI() {
        selectionStyle = .none
        backgroundColor = AppColors.bg1
        contentView.addSubview(textField)
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: AppSpacing.lg),
            textField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -AppSpacing.lg),
            textField.topAnchor.constraint(equalTo: contentView.topAnchor, constant: AppSpacing.md),
            textField.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -AppSpacing.md),
            textField.heightAnchor.constraint(greaterThanOrEqualToConstant: 36)
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onNameChanged = nil
    }

    // MARK: - Configure

    func configure(name: String) {
        textField.text = name
    }

    /// Programmatically focus the field. Used by the host controller in
    /// create-mode to mirror iOS Reminders' "tap-and-type" UX (#143).
    func beginEditing() {
        textField.becomeFirstResponder()
    }

    // MARK: - Actions

    @objc private func textChanged() {
        onNameChanged?(textField.text ?? "")
    }

    @objc private func returnTapped() {
        textField.resignFirstResponder()
    }
}
