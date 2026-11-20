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
        title: titleLabel, value: soundNameLabel, chevron: chevronView, in: contentView
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
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
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
        // Title and sound name: one line as before, or stacked from XL.
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

// MARK: - Title + value layout

/// The title and trailing value of the «Звук» and «Тема» rows (#1111). Up to
/// `.large` they share one line, exactly as before; from XL
/// (`AppTypography.stacksDenseRows`) the value moves under the title and may
/// wrap, because a long name («Bach's Badinerie», «Своя мелодия») no longer
/// fits beside the icon, the title and the chevron of a 375pt card.
struct DisclosureRowLayout {
    private let value: UILabel
    private let beside: [NSLayoutConstraint]
    private let under: [NSLayoutConstraint]

    /// Both labels are already in `contentView`; the title's leading edge is
    /// the caller's.
    init(title: UILabel, value: UILabel, chevron: UIView, in contentView: UIView) {
        self.value = value
        let gap = AppSpacing.sp2
        beside = [
            title.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            value.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -gap),
            value.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            value.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: gap)
        ]
        // Top-down with an open bottom: a row taller than its text has one
        // place for the slack, not two labels tied for it.
        under = [
            title.topAnchor.constraint(equalTo: contentView.topAnchor, constant: AppSpacing.sp3),
            title.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -gap),
            value.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
            value.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            value.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -gap),
            value.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -AppSpacing.sp3)
        ]
        // The title is one word: it never wraps, and in a row it is the value
        // that gives way.
        title.numberOfLines = 1
        title.setContentCompressionResistancePriority(.defaultHigh + 1, for: .horizontal)
        value.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    }

    func apply(_ category: UIContentSizeCategory) {
        let stacked = AppTypography.stacksDenseRows(category)
        NSLayoutConstraint.deactivate(stacked ? beside : under)
        NSLayoutConstraint.activate(stacked ? under : beside)
        value.numberOfLines = stacked ? 0 : 1
    }
}
