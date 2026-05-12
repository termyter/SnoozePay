import UIKit

/// V2 destructive "Удалить будильник" row. Tinted `pain400` so the row reads
/// as the same intent as the dedicated `ConfirmDeleteAlarmViewController` it
/// presents on tap. Selection is left enabled so the user gets a brief
/// highlight before the confirmation sheet animates up from the bottom.
final class DeleteActionCell: UITableViewCell {

    static let reuseID = "DeleteActionCell"

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        textLabel?.text = "Удалить будильник"
        textLabel?.textColor = AppColors.pain400
        textLabel?.textAlignment = .center
        textLabel?.font = AppFonts.sans(.semibold, 17)
        backgroundColor = AppColors.bg1
        selectionStyle = .default
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
