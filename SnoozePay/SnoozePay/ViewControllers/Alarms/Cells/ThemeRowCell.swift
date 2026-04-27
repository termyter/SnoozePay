import UIKit

/// "Тема будильника" disclosure row used by `CreateAlarmViewController` (#143).
///
/// Layout matches the SPRow primitive: title on the leading side, current
/// value + chevron on the trailing side. Tapping the row is wired by the
/// hosting controller via `didSelectRowAt`. The full picker lands in #151;
/// until then the controller stubs the navigation as a no-op.
final class ThemeRowCell: UITableViewCell {

    static let reuseID = "ThemeRowCell"

    // MARK: - UI

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Тема"
        label.font = AppTypography.bodyLg
        label.textColor = AppColors.fg1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let valueLabel: UILabel = {
        let label = UILabel()
        label.font = AppTypography.bodyLg
        label.textColor = AppColors.fg3
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let chevronView: UIImageView = {
        let image = UIImage(systemName: "chevron.right")?.withConfiguration(
            UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        )
        let view = UIImageView(image: image)
        view.tintColor = AppColors.fg3
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
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
        backgroundColor = AppColors.bg1
        // Match SoundCell — let the system briefly highlight the row on tap
        // so the user gets feedback before the picker pushes onto the stack.
        selectionStyle = .default

        contentView.addSubview(titleLabel)
        contentView.addSubview(chevronView)
        contentView.addSubview(valueLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: AppSpacing.lg),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            chevronView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -AppSpacing.lg),
            chevronView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            valueLabel.trailingAnchor.constraint(equalTo: chevronView.leadingAnchor, constant: -AppSpacing.sm),
            valueLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            valueLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: AppSpacing.sm
            ),

            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
    }

    // MARK: - Configure

    func configure(themeName: String) {
        valueLabel.text = themeName
    }
}
