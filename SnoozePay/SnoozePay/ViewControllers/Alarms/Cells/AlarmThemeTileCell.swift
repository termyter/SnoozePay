import UIKit

/// Single grid tile rendered by `AlarmThemePickerViewController` (V3 — #285).
///
/// Per `docs/design/snoozepay-2026-04-27/project/components/SPMore2.jsx:362-384` contains "aspectRatio":
/// the whole tile is the theme preview (135° gradient
/// for built-ins, photo / "+" for `.custom`). The name + subtitle are overlaid
/// bottom-left with a text shadow (no opaque footer band); a 22pt money-gradient
/// checkmark badge sits top-right when selected, and the selected tile gets a
/// money outline with a 2pt offset.
final class AlarmThemeTileCell: UICollectionViewCell {

    static let reuseID = "AlarmThemeTileCell"

    // MARK: - UI

    private let card: SPCard = {
        let card = SPCard(tone: .surface, padding: 0, cornerRadius: AppRadius.md)
        card.translatesAutoresizingMaskIntoConstraints = false
        card.clipsToBounds = true
        return card
    }()

    /// Theme miniature — 135° base gradient plus the bottom accent glow.
    /// Shared with the picker's preview block so tile and preview are one
    /// recipe and cannot drift apart (#463).
    private let previewView = SPThemePreviewView()

    private let imageView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.isHidden = true
        return view
    }()

    /// Flat fill of the empty `.custom` slot — `--sp-white-06` in
    /// `docs/design/snoozepay-2026-04-27/project/components/SPMore2.jsx:365`.
    /// A dynamic colour, so it follows the theme on its own (#1110).
    private let customFill: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = AppColors.whiteOverlay06
        view.isHidden = true
        return view
    }()

    /// Centered "+" symbol for the empty `.custom` slot.
    private let plusIcon: UIImageView = {
        let icon = UIImageView(image: UIImage(systemName: "plus")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 28, weight: .semibold)))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = AppColors.fg3
        icon.contentMode = .center
        icon.isHidden = true
        return icon
    }()

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = AppTypography.buttonSm
        label.textColor = .white
        label.numberOfLines = 1
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = AppFonts.sans(.medium, 10)
        label.textColor = UIColor.white.withAlphaComponent(0.75)
        label.numberOfLines = 1
        return label
    }()

    private let textStack: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 1
        stack.alignment = .leading
        return stack
    }()

    /// 22pt money-gradient checkmark badge, top-right when selected.
    ///
    /// The gradient IS the view's layer (#1110). It used to be a sublayer
    /// framed from the cell's `layoutSubviews`, but the badge sits three
    /// levels down (cell → contentView → card → badge): at that moment Auto
    /// Layout has not sized it yet, so the layer stayed 0×0 and only the bare
    /// tick showed. Stops start empty and are resolved against this view's
    /// traits in `refreshBadgeColors()` — a `CGColor` read in `setup()` bakes
    /// whichever theme `UITraitCollection.current` was (same as #553).
    private let checkmarkBadge: SPGradientView = {
        let view = SPGradientView(colors: [], locations: SPSupport.moneyGradientLocations)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 11
        view.layer.masksToBounds = true
        view.isHidden = true
        return view
    }()

    private let checkmarkIcon: UIImageView = {
        let view = UIImageView(image: UIImage(systemName: "checkmark")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.tintColor = AppColors.fgOnMoney
        view.contentMode = .center
        return view
    }()

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
        card.addSubview(previewView)
        card.addSubview(customFill)
        card.addSubview(imageView)
        card.addSubview(plusIcon)

        textStack.addArrangedSubview(nameLabel)
        textStack.addArrangedSubview(subtitleLabel)
        applyTextShadow(to: nameLabel)
        applyTextShadow(to: subtitleLabel)
        card.addSubview(textStack)

        checkmarkBadge.addSubview(checkmarkIcon)
        card.addSubview(checkmarkBadge)
        refreshBadgeColors()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (cell: AlarmThemeTileCell, _) in
            cell.refreshBadgeColors()
        }

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: contentView.topAnchor),
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            previewView.topAnchor.constraint(equalTo: card.topAnchor),
            previewView.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            previewView.bottomAnchor.constraint(equalTo: card.bottomAnchor),

            customFill.topAnchor.constraint(equalTo: card.topAnchor),
            customFill.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            customFill.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            customFill.bottomAnchor.constraint(equalTo: card.bottomAnchor),

            imageView.topAnchor.constraint(equalTo: card.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: card.bottomAnchor),

            plusIcon.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            plusIcon.centerYAnchor.constraint(equalTo: card.centerYAnchor, constant: -8),

            textStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: AppSpacing.sp2),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -AppSpacing.sp2),
            textStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -AppSpacing.sp2),

            checkmarkBadge.topAnchor.constraint(equalTo: card.topAnchor, constant: 6),
            checkmarkBadge.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -6),
            checkmarkBadge.widthAnchor.constraint(equalToConstant: 22),
            checkmarkBadge.heightAnchor.constraint(equalToConstant: 22),

            checkmarkIcon.centerXAnchor.constraint(equalTo: checkmarkBadge.centerXAnchor),
            checkmarkIcon.centerYAnchor.constraint(equalTo: checkmarkBadge.centerYAnchor)
        ])
    }

    private func applyTextShadow(to label: UILabel) {
        label.layer.shadowColor = UIColor.black.cgColor
        label.layer.shadowOpacity = 0.6
        label.layer.shadowOffset = CGSize(width: 0, height: 1)
        label.layer.shadowRadius = 4
        label.layer.masksToBounds = false
    }

    private func refreshBadgeColors() {
        checkmarkBadge.refresh(
            colors: SPSupport.moneyGradientColors(for: traitCollection),
            locations: SPSupport.moneyGradientLocations
        )
    }

    /// White + shadow over theme imagery (the canon's `#FFF` / 75%); theme
    /// inks on the flat empty custom slot, where white disappears on the light
    /// theme's `whiteOverlay06` (#1110). The canon is dark-only and paints
    /// white there because its `--sp-white-06` sits on `--sp-bg-0`.
    private func applyLabelStyle(onFlatFill: Bool) {
        nameLabel.textColor = onFlatFill ? AppColors.fg1 : .white
        subtitleLabel.textColor = onFlatFill ? AppColors.fg2 : UIColor.white.withAlphaComponent(0.75)
        let shadowOpacity: Float = onFlatFill ? 0 : 0.6
        nameLabel.layer.shadowOpacity = shadowOpacity
        subtitleLabel.layer.shadowOpacity = shadowOpacity
    }

    // MARK: - Configure

    /// - Parameters:
    ///   - theme: built-in theme to render the gradient/name/subtitle from.
    ///     Ignored for the custom slot (pass `.dawn` as a placeholder).
    ///   - isCustomSlot: when true, render the `+` affordance on a flat
    ///     `whiteOverlay06` fill with theme-ink copy (or the picked photo
    ///     thumbnail with white copy).
    ///   - isSelected: money outline + offset + checkmark badge.
    ///   - customImage: thumbnail for the `.custom` slot when a photo exists.
    func configure(theme: AlarmTheme, isCustomSlot: Bool, isSelected: Bool, customImage: UIImage?) {
        imageView.image = nil
        imageView.isHidden = true
        plusIcon.isHidden = true
        customFill.isHidden = true
        previewView.isHidden = false
        previewView.alpha = 1.0
        var onFlatFill = false

        let displayTheme: AlarmTheme
        if isCustomSlot {
            displayTheme = AlarmTheme.custom(imagePath: URL(fileURLWithPath: "/"))
            if let image = customImage {
                imageView.image = image
                imageView.isHidden = false
                previewView.isHidden = true
            } else {
                previewView.isHidden = true
                customFill.isHidden = false
                plusIcon.isHidden = false
                onFlatFill = true
            }
        } else if case .custom(let url) = theme {
            displayTheme = theme
            if let image = AlarmThemeImageStore.loadImage(at: url) {
                imageView.image = image
                imageView.isHidden = false
                previewView.isHidden = true
            } else {
                previewView.apply(theme: .dawn)
            }
        } else {
            displayTheme = theme
            previewView.apply(theme: theme)
        }
        applyLabelStyle(onFlatFill: onFlatFill)

        nameLabel.text = displayTheme.displayName
        subtitleLabel.text = AlarmThemeSubtitles.subtitle(for: displayTheme)

        checkmarkBadge.isHidden = !isSelected
        // Money outline + 2pt offset on the selected tile
        // (`docs/design/snoozepay-2026-04-27/project/components/SPMore2.jsx:366-367` contains "outlineOffset").
        if isSelected {
            card.layer.borderColor = AppColors.money500.cgColor
            card.layer.borderWidth = 2
        } else {
            card.layer.borderColor = AppColors.stroke1.cgColor
            card.layer.borderWidth = hairlineWidth
        }
    }
}
