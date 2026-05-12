import UIKit

/// V2 "Громкость" row: leading volume icon + title + trailing "{N}%" meta +
/// chevron. Matches the settings-group row pattern from `SPScreensV2.jsx`.
/// Tapping pushes `VolumePickerViewController` (wired by the parent).
final class VolumeCell: UITableViewCell {

    static let reuseID = "VolumeCell"

    // MARK: - UI

    private let iconView: UIImageView = {
        let image = UIImage(systemName: "speaker.wave.3.fill")?.withConfiguration(
            UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        )
        let view = UIImageView(image: image)
        view.tintColor = AppColors.fg3
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Громкость"
        label.font = AppTypography.bodyLg
        label.textColor = AppColors.fg1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let valueLabel: UILabel = {
        let label = UILabel()
        label.font = AppTypography.meta
        label.textColor = AppColors.fg3
        label.textAlignment = .right
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

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        backgroundColor = AppColors.bg1
        selectionStyle = .default

        contentView.addSubview(iconView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(chevronView)
        contentView.addSubview(valueLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: AppSpacing.sp4),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: AppSpacing.sp3),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            chevronView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -AppSpacing.sp4),
            chevronView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            valueLabel.trailingAnchor.constraint(equalTo: chevronView.leadingAnchor, constant: -AppSpacing.sp2),
            valueLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            valueLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: AppSpacing.sp2
            ),

            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 48)
        ])
    }

    // MARK: - Configure

    /// Render the trailing summary as "{N}%" plus a "· плавно" suffix when
    /// the per-alarm fade-in toggle is on so the user can spot the option
    /// at a glance without having to drill into the picker.
    func configure(volume: Float, fadeIn: Bool) {
        let pct = Int(round(min(max(volume, 0), 1) * 100))
        if fadeIn {
            valueLabel.text = "\(pct)% · плавно"
        } else {
            valueLabel.text = "\(pct)%"
        }
    }
}
