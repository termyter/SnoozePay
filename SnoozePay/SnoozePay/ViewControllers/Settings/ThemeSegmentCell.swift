import UIKit

/// Reusable settings row that owns its `UISegmentedControl`. Replaces the
/// previous pattern in `SettingsViewController` where a single shared segment
/// instance was repeatedly removed/re-added across cell reuse — fragile, and
/// guaranteed to lose the control to the most-recently-rendered cell.
///
/// The cell is configured by the data source via `configure(selectedIndex:onChange:)`
/// and forwards segment events through the closure.
final class ThemeSegmentCell: UITableViewCell {

    static let reuseID = "ThemeSegmentCell"

    // MARK: - UI

    private let iconContainer: UIView = {
        let view = UIView()
        view.backgroundColor = AppColors.info500
        view.layer.cornerRadius = 7
        view.layer.masksToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "moon.fill")?.withConfiguration(
            UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        )
        imageView.tintColor = .white
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Тема"
        label.font = AppTypography.bodyLg
        label.textColor = AppColors.fg1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let segmentControl: UISegmentedControl = {
        let segment = UISegmentedControl(items: ["Системная", "Светлая", "Тёмная"])
        segment.selectedSegmentTintColor = AppColors.info500
        segment.translatesAutoresizingMaskIntoConstraints = false
        return segment
    }()

    /// Forwarded on every `valueChanged` event from the segment.
    private var onChange: ((Int) -> Void)?

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
        selectionStyle = .none

        iconContainer.addSubview(iconImageView)
        contentView.addSubview(iconContainer)
        contentView.addSubview(titleLabel)
        contentView.addSubview(segmentControl)

        segmentControl.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)

        NSLayoutConstraint.activate([
            iconContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: AppSpacing.lg),
            iconContainer.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: 30),
            iconContainer.heightAnchor.constraint(equalToConstant: 30),

            iconImageView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: AppSpacing.md),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            segmentControl.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -AppSpacing.lg),
            segmentControl.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            segmentControl.widthAnchor.constraint(equalToConstant: 220),
            segmentControl.leadingAnchor.constraint(
                greaterThanOrEqualTo: titleLabel.trailingAnchor,
                constant: AppSpacing.sm
            )
        ])
    }

    // MARK: - Configure

    /// Set the currently selected segment and the change handler. Safe to call
    /// repeatedly on cell reuse — the previous handler is dropped.
    func configure(selectedIndex: Int, onChange: @escaping (Int) -> Void) {
        segmentControl.selectedSegmentIndex = selectedIndex
        self.onChange = onChange
    }

    // MARK: - Actions

    @objc private func segmentChanged() {
        onChange?(segmentControl.selectedSegmentIndex)
    }

    // MARK: - Reuse

    override func prepareForReuse() {
        super.prepareForReuse()
        // Drop the previous closure so a recycled cell doesn't fire its old
        // owner's handler before `configure` is called again.
        onChange = nil
    }
}
