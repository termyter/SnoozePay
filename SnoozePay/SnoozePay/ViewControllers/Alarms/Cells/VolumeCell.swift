import UIKit

/// "Громкость" row on the create / edit alarm form (#150).
///
/// Mirrors the chrome of `SoundCell` so the new row reads as the same
/// primitive — title on the left, current volume + optional fade-in label
/// on the right, chevron disclosure. Tapping pushes the
/// `VolumePickerViewController` (handled by the parent `didSelectRowAt`).
final class VolumeCell: UITableViewCell {

    static let reuseID = "VolumeCell"

    // MARK: - UI

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Громкость"
        label.font = UIFont.systemFont(ofSize: 17)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let valueLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 17)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .right
        return label
    }()

    private let chevronView: UIImageView = {
        let image = UIImage(systemName: "chevron.right")?.withConfiguration(
            UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        )
        let view = UIImageView(image: image)
        view.tintColor = .tertiaryLabel
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
        backgroundColor = .secondarySystemBackground
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
