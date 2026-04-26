import UIKit

/// Centred red "Удалить будильник" row, shown only in edit mode.
/// Mirrors the iOS Settings destructive-row pattern (e.g. Calendar's
/// "Delete Event" — selectionStyle = .default gives tactile feedback before
/// the confirmation sheet appears).
final class DeleteActionCell: UITableViewCell {

    static let reuseID = "DeleteActionCell"

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        textLabel?.text = "Удалить будильник"
        textLabel?.textColor = .systemRed
        textLabel?.textAlignment = .center
        textLabel?.font = UIFont.systemFont(ofSize: 17, weight: .regular)
        backgroundColor = .secondarySystemBackground
        selectionStyle = .default
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
