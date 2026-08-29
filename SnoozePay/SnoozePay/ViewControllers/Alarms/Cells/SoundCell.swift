import UIKit

/// V2 «Звук» row: leading sound icon + title + trailing sound name (meta) +
/// chevron. The inline preview play button is dropped — the dedicated
/// `SoundPickerViewController` exposes per-row previews so the form-level
/// row stays clean. Matches `SPScreensV2.jsx` lines 574-578.
final class SoundCell: UITableViewCell {

    static let reuseID = "SoundCell"

    // MARK: - UI

    private let iconView: UIImageView = {
        let image = UIImage(systemName: "speaker.wave.2.fill")?.withConfiguration(
            UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        )
        let view = UIImageView(image: image)
        view.tintColor = AppColors.fg3
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = Localized.text("create_alarm.sound.title")
        label.font = AppTypography.bodyLg
        label.textColor = AppColors.fg1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let soundNameLabel: UILabel = {
        let label = UILabel()
        label.font = AppTypography.meta
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

    // MARK: - Callbacks

    /// Retained for backwards compatibility — preview now ships on the
    /// dedicated picker screen, so this fires only if the host wires it.
    var onPreviewTapped: (() -> Void)?

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
        selectionStyle = .default

        contentView.addSubview(iconView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(chevronView)
        contentView.addSubview(soundNameLabel)

        // 20pt horizontal insets — the V2 list-row rule `padding="4px 20px"`
        // (#231).
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: AppSpacing.sp5),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: AppSpacing.sp3),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            chevronView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -AppSpacing.sp5),
            chevronView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            soundNameLabel.trailingAnchor.constraint(equalTo: chevronView.leadingAnchor, constant: -AppSpacing.sp2),
            soundNameLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            soundNameLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: AppSpacing.sp2
            ),

            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 48)
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onPreviewTapped = nil
    }

    // MARK: - Configure

    func configure(soundName: String) {
        soundNameLabel.text = soundName
    }
}
