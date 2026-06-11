import UIKit

/// Reusable icon + title row for the Settings table (history, balance, info,
/// contact rows). Replaces the previous `makeIconRow` factory that built
/// `UITableViewCell(style:reuseIdentifier: nil)` on every `cellForRowAt:` —
/// nil-identifier cells are never recycled, so each reload leaked a fresh
/// cell hierarchy (#203).
///
/// `configure` resets every mutable bit of state, so no `prepareForReuse`
/// override is needed: a recycled cell is always fully re-specified before
/// it re-enters the viewport.
final class SettingsIconRowCell: UITableViewCell {

    static let reuseID = "SettingsIconRowCell"

    // MARK: - UI

    private let iconContainer: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 7
        view.layer.masksToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.tintColor = .white
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = AppTypography.bodyLg
        label.textColor = AppColors.fg1
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = AppTypography.meta
        label.textColor = AppColors.fg3
        label.isHidden = true
        return label
    }()

    /// Right-aligned value (the balance amount). Hidden unless configured.
    private let trailingLabel: UILabel = {
        let label = UILabel()
        label.font = AppTypography.moneyMd
        label.isHidden = true
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
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

        iconContainer.addSubview(iconImageView)

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 2

        let mainStack = UIStackView(arrangedSubviews: [iconContainer, textStack, trailingLabel])
        mainStack.axis = .horizontal
        mainStack.spacing = AppSpacing.md
        mainStack.alignment = .center
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(mainStack)

        NSLayoutConstraint.activate([
            iconContainer.widthAnchor.constraint(equalToConstant: 30),
            iconContainer.heightAnchor.constraint(equalToConstant: 30),
            iconImageView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),

            mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: AppSpacing.lg),
            mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -AppSpacing.lg),
            mainStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }

    // MARK: - Configure

    /// Fully re-specifies the row. Every property is written unconditionally
    /// so state from a previous tenant of this cell can't survive recycling.
    func configure(
        systemName: String,
        iconColor: UIColor,
        title: String,
        subtitle: String? = nil,
        trailingText: String? = nil,
        trailingColor: UIColor = AppColors.money500,
        accessory: UITableViewCell.AccessoryType = .none,
        selectionStyle: UITableViewCell.SelectionStyle = .default
    ) {
        iconContainer.backgroundColor = iconColor
        iconImageView.image = UIImage(systemName: systemName)?.withConfiguration(
            UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        )
        titleLabel.text = title

        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle == nil

        trailingLabel.text = trailingText
        trailingLabel.textColor = trailingColor
        trailingLabel.isHidden = trailingText == nil

        accessoryType = accessory
        self.selectionStyle = selectionStyle
    }
}
