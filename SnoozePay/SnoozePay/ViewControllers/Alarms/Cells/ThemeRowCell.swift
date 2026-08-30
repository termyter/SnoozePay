import UIKit

/// V2 «Тема» disclosure row: leading 28×28 gradient thumbnail + title +
/// trailing theme-name meta + chevron. Matches `SPScreensV2.jsx` lines
/// 579-584. The thumbnail tracks the currently-selected theme so the user
/// sees a live preview of what they've picked without having to enter the
/// theme picker.
final class ThemeRowCell: UITableViewCell {

    static let reuseID = "ThemeRowCell"

    // MARK: - UI

    /// Thumbnail container — 28×28 with a theme gradient (or photo) drawn
    /// inside. Rounded `AppRadius.xs` corners so the chip reads as a
    /// "stamp" of the firing screen.
    private let thumbnail: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = AppRadius.xs
        view.layer.masksToBounds = true
        view.backgroundColor = AppColors.bg2
        return view
    }()

    private let thumbnailImageView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.isHidden = true
        return view
    }()

    private var thumbnailGradient: CAGradientLayer?

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = Localized.text("create_alarm.theme.title")
        label.font = AppTypography.bodyLg
        label.textColor = AppColors.fg1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let valueLabel: UILabel = {
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

    // MARK: - Init

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        thumbnailGradient?.frame = thumbnail.bounds
    }

    // MARK: - Setup

    private func setupUI() {
        backgroundColor = AppColors.bg1
        selectionStyle = .default

        thumbnail.addSubview(thumbnailImageView)

        contentView.addSubview(thumbnail)
        contentView.addSubview(titleLabel)
        contentView.addSubview(chevronView)
        contentView.addSubview(valueLabel)

        // 20pt horizontal insets — the V2 list-row rule `padding="4px 20px"`
        // (#231).
        NSLayoutConstraint.activate([
            thumbnail.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: AppSpacing.cardHorizontalPadding),
            thumbnail.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            thumbnail.widthAnchor.constraint(equalToConstant: 28),
            thumbnail.heightAnchor.constraint(equalToConstant: 28),

            thumbnailImageView.topAnchor.constraint(equalTo: thumbnail.topAnchor),
            thumbnailImageView.leadingAnchor.constraint(equalTo: thumbnail.leadingAnchor),
            thumbnailImageView.trailingAnchor.constraint(equalTo: thumbnail.trailingAnchor),
            thumbnailImageView.bottomAnchor.constraint(equalTo: thumbnail.bottomAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: thumbnail.trailingAnchor, constant: AppSpacing.sp3),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            chevronView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -AppSpacing.cardHorizontalPadding),
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

    /// Legacy two-arg signature retained for the existing `+Sections` call
    /// sites. The thumbnail falls back to the default Dawn gradient.
    func configure(themeName: String) {
        configure(theme: .dawn, themeName: themeName)
    }

    /// V2 signature: render the theme's actual gradient/photo into the
    /// leading thumbnail so the row reads as a live preview of the current
    /// selection.
    func configure(theme: AlarmTheme, themeName: String) {
        valueLabel.text = themeName
        thumbnailGradient?.removeFromSuperlayer()
        thumbnailGradient = nil
        thumbnailImageView.image = nil
        thumbnailImageView.isHidden = true

        if case .custom(let url) = theme, let image = AlarmThemeImageStore.loadImage(at: url) {
            thumbnailImageView.image = image
            thumbnailImageView.isHidden = false
        } else if let colors = AlarmThemeRendering.gradientColors(for: theme) {
            let layer = CAGradientLayer()
            layer.colors = colors
            layer.locations = AlarmThemeRendering.gradientLocations(for: theme)
            layer.startPoint = CGPoint(x: 0.0, y: 0.0)
            layer.endPoint = CGPoint(x: 1.0, y: 1.0)
            layer.frame = thumbnail.bounds
            thumbnail.layer.insertSublayer(layer, at: 0)
            thumbnailGradient = layer
        }
    }
}
