import UIKit

/// Read-only preview row showing how penalties grow ("1-е: 50₽ → 2-е: 100₽ ...")
/// when progressive scale is enabled. Surfaces only when `ProgressiveScaleCell`
/// is toggled on.
final class ProgressivePreviewCell: UITableViewCell {

    static let reuseID = "ProgressivePreviewCell"

    // MARK: - UI

    private let previewLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 13)
        label.textColor = AppColors.accentOrange
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
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
        backgroundColor = .secondarySystemBackground
        selectionStyle = .none
        contentView.addSubview(previewLabel)
        NSLayoutConstraint.activate([
            previewLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: AppSpacing.lg),
            previewLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -AppSpacing.lg),
            previewLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: AppSpacing.sm),
            previewLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -AppSpacing.sm)
        ])
    }

    // MARK: - Configure

    func configure(text: String) {
        previewLabel.text = text
    }
}
