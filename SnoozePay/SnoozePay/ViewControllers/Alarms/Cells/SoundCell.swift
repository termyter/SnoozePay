import UIKit

/// Sound row: title on the left, current sound name + play button + chevron
/// disclosure on the right. Tapping the row pushes `SoundPickerViewController`
/// (handled by the controller's `didSelectRowAt`); tapping the play button
/// fires a preview without leaving the screen.
final class SoundCell: UITableViewCell {

    static let reuseID = "SoundCell"

    // MARK: - UI

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Звук"
        label.font = UIFont.systemFont(ofSize: 17)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let soundNameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 17)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let playButton: UIButton = {
        let button = UIButton(type: .system)
        let image = UIImage(systemName: "play.circle.fill")?.withConfiguration(
            UIImage.SymbolConfiguration(pointSize: 24, weight: .medium)
        )
        button.setImage(image, for: .normal)
        button.tintColor = AppColors.accentBlue
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
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

    // MARK: - Callbacks

    var onPreviewTapped: (() -> Void)?

    // MARK: - Init

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
        playButton.addTarget(self, action: #selector(previewTapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupUI() {
        backgroundColor = .secondarySystemBackground
        // Use the system selection so the row briefly highlights on tap before
        // navigating to the sound picker.
        selectionStyle = .default

        contentView.addSubview(titleLabel)
        contentView.addSubview(chevronView)
        contentView.addSubview(playButton)
        contentView.addSubview(soundNameLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: AppSpacing.lg),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            chevronView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -AppSpacing.lg),
            chevronView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            playButton.trailingAnchor.constraint(equalTo: chevronView.leadingAnchor, constant: -AppSpacing.sm),
            playButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            soundNameLabel.trailingAnchor.constraint(
                equalTo: playButton.leadingAnchor, constant: -AppSpacing.sm
            ),
            soundNameLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            soundNameLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: AppSpacing.sm
            ),

            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
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

    // MARK: - Actions

    @objc private func previewTapped() {
        onPreviewTapped?()
    }
}
