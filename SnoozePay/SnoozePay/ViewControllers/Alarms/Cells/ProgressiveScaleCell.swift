import UIKit

/// V2 "Прогрессивный режим" toggle row with leading flame icon. The icon
/// tints `pain400` when the toggle is on (matching `SPScreensV2.jsx` lines
/// 622) and falls back to `fg3` when off so the row reads as "armed" /
/// "disarmed" at a glance.
///
/// The row also surfaces the rationale subtitle ("Каждое откладывание — в 2
/// раза дороже") so the user understands the cost ramp before flipping it.
final class ProgressiveScaleCell: UITableViewCell {

    static let reuseID = "ProgressiveScaleCell"

    // MARK: - UI

    private let iconView: UIImageView = {
        let image = UIImage(systemName: "flame.fill")?.withConfiguration(
            UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        )
        let view = UIImageView(image: image)
        view.tintColor = AppColors.fg3
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Прогрессивный режим"
        label.font = AppTypography.bodyLg
        label.textColor = AppColors.fg1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Каждое откладывание — в 2 раза дороже"
        label.font = AppTypography.meta
        label.textColor = AppColors.fg3
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let textStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
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
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(subtitleLabel)

        contentView.addSubview(iconView)
        contentView.addSubview(textStack)
        contentView.addSubview(toggle)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: AppSpacing.sp4),
            iconView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),

            textStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: AppSpacing.sp3),
            textStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: AppSpacing.sp3),
            textStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -AppSpacing.sp3),

            toggle.leadingAnchor.constraint(greaterThanOrEqualTo: textStack.trailingAnchor, constant: AppSpacing.sp3),
            toggle.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -AppSpacing.sp4),
            toggle.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onToggled = nil
    }

    // MARK: - Configure

    func configure(isOn: Bool) {
        toggle.isOn = isOn
        iconView.tintColor = isOn ? AppColors.pain400 : AppColors.fg3
    }

    // MARK: - Actions

    @objc private func toggled() {
        iconView.tintColor = toggle.isOn ? AppColors.pain400 : AppColors.fg3
        onToggled?(toggle.isOn)
    }
}
