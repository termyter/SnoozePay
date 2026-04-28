import UIKit

/// Single grid tile rendered by `AlarmThemePickerViewController` (#151).
///
/// Top of the tile previews the theme (gradient layer for built-ins, photo
/// or "+ icon" for `.custom`); the footer band carries the uppercased name
/// and a checkmark when selected. The tile uses `SPCard(tone: .surface,
/// padding: 0, cornerRadius: AppRadius.md)` so it shares the design system's
/// shadow + stroke recipe with the rest of the create-form surfaces.
final class AlarmThemeTileCell: UICollectionViewCell {

    static let reuseID = "AlarmThemeTileCell"

    // MARK: - UI

    private let card: SPCard = {
        let card = SPCard(tone: .surface, padding: 0, cornerRadius: AppRadius.md)
        card.translatesAutoresizingMaskIntoConstraints = false
        card.clipsToBounds = true
        return card
    }()

    private let gradientView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.masksToBounds = true
        return view
    }()

    private let imageView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.isHidden = true
        return view
    }()

    /// Centered "+" symbol for the empty `.custom` slot. Hidden the moment a
    /// custom image is picked so the user gets a thumbnail preview.
    private let plusIcon: UIImageView = {
        let icon = UIImageView(image: UIImage(systemName: "plus")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 28, weight: .semibold)))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = AppColors.fg2
        icon.contentMode = .center
        icon.isHidden = true
        return icon
    }()

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.attributedText = nil
        label.textColor = AppColors.fg1
        return label
    }()

    /// `bg2` chrome at the bottom of the tile holds the name + checkmark so
    /// the type stays legible against any underlying gradient or photo.
    private let footerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = AppColors.bg2.withAlphaComponent(0.92)
        return view
    }()

    private let checkmark: UIImageView = {
        let view = UIImageView(image: UIImage(systemName: "checkmark.circle.fill")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 22, weight: .bold)))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.tintColor = AppColors.money500
        view.isHidden = true
        return view
    }()

    private var gradientLayer: CAGradientLayer?

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        contentView.addSubview(card)
        card.addSubview(gradientView)
        card.addSubview(imageView)
        card.addSubview(plusIcon)
        card.addSubview(footerView)
        footerView.addSubview(nameLabel)
        footerView.addSubview(checkmark)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: contentView.topAnchor),
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            gradientView.topAnchor.constraint(equalTo: card.topAnchor),
            gradientView.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            gradientView.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            gradientView.bottomAnchor.constraint(equalTo: card.bottomAnchor),

            imageView.topAnchor.constraint(equalTo: card.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: card.bottomAnchor),

            plusIcon.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            plusIcon.centerYAnchor.constraint(equalTo: card.centerYAnchor, constant: -10),

            footerView.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            footerView.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            footerView.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            footerView.heightAnchor.constraint(equalToConstant: 28),

            nameLabel.centerYAnchor.constraint(equalTo: footerView.centerYAnchor),
            nameLabel.leadingAnchor.constraint(equalTo: footerView.leadingAnchor, constant: AppSpacing.sp3),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: checkmark.leadingAnchor, constant: -AppSpacing.sp2),

            checkmark.centerYAnchor.constraint(equalTo: footerView.centerYAnchor),
            checkmark.trailingAnchor.constraint(equalTo: footerView.trailingAnchor, constant: -AppSpacing.sp2),
            checkmark.widthAnchor.constraint(equalToConstant: 24),
            checkmark.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer?.frame = gradientView.bounds
    }

    // MARK: - Configure

    /// - Parameters:
    ///   - theme: built-in theme to render the gradient/name from. Ignored
    ///     for the custom slot (pass `.dawn` as a placeholder).
    ///   - isCustomSlot: when true, render the `+` affordance plus a dimmed
    ///     placeholder gradient. When the user has already picked a photo,
    ///     pass `customImage` to surface the thumbnail instead.
    ///   - isSelected: highlights the tile (money-tinted border + checkmark).
    ///   - customImage: thumbnail for the `.custom` slot when a photo has
    ///     been picked previously. nil → "+ Своё фото" placeholder.
    func configure(theme: AlarmTheme, isCustomSlot: Bool, isSelected: Bool, customImage: UIImage?) {
        // Reset prior state so recycled cells don't keep the previous tile's
        // gradient / image.
        gradientLayer?.removeFromSuperlayer()
        gradientLayer = nil
        imageView.image = nil
        imageView.isHidden = true
        plusIcon.isHidden = true

        let displayName: String
        if isCustomSlot {
            displayName = AlarmTheme.custom(imagePath: URL(fileURLWithPath: "/")).displayName
            if let image = customImage {
                imageView.image = image
                imageView.isHidden = false
            } else {
                installGradient(for: .dawn)
                gradientView.alpha = 0.4 // dim the placeholder so "+" pops
                plusIcon.isHidden = false
            }
        } else if case .custom(let url) = theme {
            displayName = theme.displayName
            if let image = AlarmThemeImageStore.loadImage(at: url) {
                imageView.image = image
                imageView.isHidden = false
            } else {
                installGradient(for: .dawn)
            }
        } else {
            displayName = theme.displayName
            installGradient(for: theme)
            gradientView.alpha = 1.0
        }

        nameLabel.attributedText = NSAttributedString(
            string: displayName.uppercased(),
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: AppColors.fg1
            ]
        )

        checkmark.isHidden = !isSelected
        // Outline the selected tile with a money-tinted border for an extra
        // affordance beyond the checkmark.
        if isSelected {
            card.layer.borderColor = AppColors.money500.cgColor
            card.layer.borderWidth = 2
        } else {
            card.layer.borderWidth = 0
        }
    }

    private func installGradient(for theme: AlarmTheme) {
        guard let colors = AlarmThemeRendering.gradientColors(for: theme) else { return }
        let layer = CAGradientLayer()
        layer.colors = colors
        layer.locations = AlarmThemeRendering.gradientLocations(for: theme)
        layer.startPoint = CGPoint(x: 0.5, y: 0.0)
        layer.endPoint = CGPoint(x: 0.5, y: 1.0)
        layer.frame = gradientView.bounds
        gradientView.layer.insertSublayer(layer, at: 0)
        gradientLayer = layer
    }
}
