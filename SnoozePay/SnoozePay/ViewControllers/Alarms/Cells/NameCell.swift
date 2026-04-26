import UIKit

/// Single-line text input cell for the alarm's display name.
final class NameCell: UITableViewCell {

    static let reuseID = "NameCell"

    // MARK: - UI

    private let textField: UITextField = {
        let field = UITextField()
        field.placeholder = "Название"
        field.font = UIFont.systemFont(ofSize: 17)
        field.translatesAutoresizingMaskIntoConstraints = false
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
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupUI() {
        selectionStyle = .none
        backgroundColor = .secondarySystemBackground
        contentView.addSubview(textField)
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: AppSpacing.lg),
            textField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -AppSpacing.lg),
            textField.topAnchor.constraint(equalTo: contentView.topAnchor),
            textField.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            textField.heightAnchor.constraint(equalToConstant: 48)
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

    // MARK: - Actions

    @objc private func textChanged() {
        onNameChanged?(textField.text ?? "")
    }
}
