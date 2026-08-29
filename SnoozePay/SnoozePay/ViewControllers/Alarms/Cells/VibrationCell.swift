import UIKit

/// V2 «Вибрация» toggle row. Uses the brand `SPSwitch` so the on-state reads
/// money-tinted instead of the platform green, matching the V2 settings group
/// in `SPScreensV2.jsx` lines 585-590.
final class VibrationCell: UITableViewCell {

    static let reuseID = "VibrationCell"

    // MARK: - UI

    private let iconView: UIImageView = {
        let image = UIImage(systemName: "bell")?.withConfiguration(
            UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        )
        let view = UIImageView(image: image)
        view.tintColor = AppColors.fg3
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = Localized.text("create_alarm.vibration.title")
        label.font = AppTypography.bodyLg
        label.textColor = AppColors.fg1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let toggle = SPSwitch()

    // MARK: - Callbacks

    var onToggled: ((Bool) -> Void)?

    // MARK: - Init

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
        toggle.addTarget(self, action: #selector(toggled), for: .valueChanged)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        backgroundColor = AppColors.bg1
        selectionStyle = .none
        toggle.translatesAutoresizingMaskIntoConstraints = false
        // Without this VoiceOver announces the brand `SPSwitch` as the generic
        // «Переключатель»; the adjacent title reads separately but the switch
        // itself carries no context. Mirror AlarmCell's contextual-label pattern
        // (#425) so the control is self-describing.
        toggle.accessibilityLabel = titleLabel.text

        contentView.addSubview(iconView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(toggle)

        // 20pt horizontal insets — the V2 list-row rule `padding="4px 20px"`
        // (#231).
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: AppSpacing.sp5),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: AppSpacing.sp3),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            toggle.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -AppSpacing.sp5),
            toggle.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 48)
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onToggled = nil
    }

    // MARK: - Configure

    func configure(isOn: Bool) {
        toggle.isOn = isOn
    }

    // MARK: - Actions

    @objc private func toggled() {
        onToggled?(toggle.isOn)
    }
}
