import UIKit

/// V2 «Звук» row: leading sound icon + title + trailing sound name (meta) +
/// chevron. The inline preview play button is dropped — the dedicated
/// `SoundPickerViewController` exposes per-row previews so the form-level
/// row stays clean. Matches
/// `docs/design/snoozepay-2026-04-27/project/components/SPScreensV2.jsx:611-615` contains "Soft Dawn</span>".
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
        label.font = AppTypography.scaledBodyLg
        label.adjustsFontForContentSizeCategory = true
        label.textColor = AppColors.fg1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let soundNameLabel: UILabel = {
        let label = UILabel()
        label.font = AppTypography.scaledMeta
        label.adjustsFontForContentSizeCategory = true
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

    private lazy var rowLayout = DisclosureRowLayout(
        icon: iconView, title: titleLabel, value: soundNameLabel, chevron: chevronView, in: contentView
    )

    // MARK: - Init

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (cell: SoundCell, _) in
            cell.rowLayout.apply(cell.traitCollection.preferredContentSizeCategory)
        }
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

        // 20pt horizontal insets. NOT a canon rule: canon wraps these rows in
        // `SPCard padding={4}`
        // (`docs/design/snoozepay-2026-04-27/project/components/SPMore2.jsx:226` contains "SPCard padding={4}"),
        // i.e. 4pt. The 20 is the app's own, held so all ten cells of the
        // form share one inset — see `AppSpacing.cardHorizontalPadding`
        // (#231, #672, #685).
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: AppSpacing.cardHorizontalPadding
            ),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: AppSpacing.sp3),

            chevronView.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -AppSpacing.cardHorizontalPadding
            ),
            chevronView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 48)
        ])
        // Icon, title and sound name: one line as before, or stacked from XL.
        rowLayout.apply(traitCollection.preferredContentSizeCategory)
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
