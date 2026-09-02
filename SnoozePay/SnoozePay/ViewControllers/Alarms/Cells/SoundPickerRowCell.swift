import UIKit

/// Single-sound row used by `SoundPickerViewController` (V3 — #285).
///
/// Layout per `SPMore.jsx:354-382`: a 36×36 leading icon tile (money-gradient
/// when the row is selected, faint overlay otherwise) → title (h4) + subtitle
/// (meta) stack → trailing 20pt money checkmark on the selected row. Rows sit
/// inside a single shared `SPCard` owned by the view-controller, so each cell
/// only draws a hairline bottom divider (suppressed on the last row) rather
/// than its own card chrome. Preview playback lives in a separate bottom
/// «Превью» player card, NOT on the row — so there's no per-row play button.
///
/// A disabled variant renders the «Своя мелодия · скоро» slot dimmed and
/// non-interactive.
final class SoundPickerRowCell: UITableViewCell {

    static let reuseID = "SoundPickerRowCell"

    // MARK: - UI

    /// 36×36 rounded icon tile. Fill flips to the money gradient when selected.
    private let iconTile: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 10
        view.layer.masksToBounds = true
        return view
    }()

    private let iconTileGradient = CAGradientLayer()

    private let iconView: UIImageView = {
        let view = UIImageView(image: UIImage(systemName: "music.note")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .center
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = AppTypography.h4
        label.textColor = AppColors.fg1
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = AppTypography.meta
        label.textColor = AppColors.fg3
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let checkmark: UIImageView = {
        let view = UIImageView()
        view.image = UIImage(systemName: "checkmark")?.withConfiguration(
            UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        )
        view.tintColor = AppColors.money500
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let divider: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = AppColors.whiteOverlay08
        return view
    }()

    private let textStack: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 2
        stack.alignment = .leading
        stack.isUserInteractionEnabled = false
        return stack
    }()

    private var lastIsSelected = false
    private var dividerHeightConstraint: NSLayoutConstraint?

    // MARK: - Init

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: SoundPickerRowCell, _) in
                view.refreshIconTile()
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupUI() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none

        iconTileGradient.startPoint = SPSupport.gradientStart
        iconTileGradient.endPoint = SPSupport.gradientEnd
        iconTile.layer.insertSublayer(iconTileGradient, at: 0)
        iconTile.addSubview(iconView)

        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(subtitleLabel)

        contentView.addSubview(iconTile)
        contentView.addSubview(textStack)
        contentView.addSubview(checkmark)
        contentView.addSubview(divider)

        // 14×16 inset per JSX (padding "14px 16px").
        let hInset = AppSpacing.sp4
        NSLayoutConstraint.activate([
            iconTile.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: hInset),
            iconTile.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconTile.widthAnchor.constraint(equalToConstant: 36),
            iconTile.heightAnchor.constraint(equalToConstant: 36),

            iconView.centerXAnchor.constraint(equalTo: iconTile.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconTile.centerYAnchor),

            textStack.leadingAnchor.constraint(equalTo: iconTile.trailingAnchor, constant: AppSpacing.sp3),
            textStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            textStack.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 14),
            textStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -14),

            checkmark.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -hInset),
            checkmark.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            checkmark.widthAnchor.constraint(equalToConstant: 20),
            checkmark.heightAnchor.constraint(equalToConstant: 20),

            textStack.trailingAnchor.constraint(
                lessThanOrEqualTo: checkmark.leadingAnchor, constant: -AppSpacing.sp3
            ),

            divider.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: hInset),
            divider.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -hInset),
            divider.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 64)
        ])

        // Same shape as `SPRow`: the constraint is built before the cell has
        // a screen, so it starts at the provisional width and is re-read in
        // `layoutSubviews`. A literal here is how the two sites drifted apart
        // in the first place — #689 is about there being one source.
        let dividerHeight = divider.heightAnchor.constraint(
            equalToConstant: AppHairline.provisionalWidth
        )
        dividerHeight.isActive = true
        dividerHeightConstraint = dividerHeight
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        iconTileGradient.frame = iconTile.bounds
        // Unconditional, as it was before #689 — see the note in
        // `SPRow.layoutSubviews`. Two reasons, and neither is "cells that
        // never appear": those draw nothing, and cells that do appear get a
        // windowed pass either way. What a `window != nil` guard would
        // actually cost is (1) a provisional width left in place with no log
        // and no assertion — a wrong value with a nicer name, by this
        // constant's own docstring — and (2) self-sizing:
        // `SoundPickerViewController` sets `rowHeight = .automaticDimension`,
        // and the table measures a cell before it is in the window hierarchy.
        // Not `UITourLauncher`, which mounts its screen as the window root
        // (`UITourLauncher.mount`), and not `systemLayoutSizeFitting`, which
        // no call site invokes on this cell — an earlier revision of this
        // comment claimed both. Written only on change.
        guard let dividerHeight = dividerHeightConstraint else { return }
        let width = hairlineWidth
        if dividerHeight.constant != width {
            dividerHeight.constant = width
        }
    }

    @available(iOS, deprecated: 17.0, message: "Replaced by registerForTraitChanges; kept for iOS 15/16.")
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if #available(iOS 17.0, *) { return }
        refreshIconTile()
    }

    private func refreshIconTile() {
        if lastIsSelected {
            iconTileGradient.colors = SPSupport.moneyGradientColors
            iconTileGradient.locations = SPSupport.moneyGradientLocations
            iconTileGradient.isHidden = false
            iconTile.backgroundColor = .clear
            iconView.tintColor = AppColors.fgOnMoney
        } else {
            iconTileGradient.isHidden = true
            iconTile.backgroundColor = AppColors.whiteOverlay06
            iconView.tintColor = AppColors.fg3
        }
    }

    // MARK: - Configure

    /// - Parameters:
    ///   - name: sound display name.
    ///   - subtitle: descriptive copy («Тёплый рассвет с птицами»).
    ///   - isSelected: money-gradient icon tile + trailing checkmark.
    ///   - isLast: suppress the hairline divider on the final row.
    ///   - isEnabled: `false` for the «Своя мелодия · скоро» slot — dims the
    ///     row and lets the controller skip selection.
    func configure(
        name: String,
        subtitle: String,
        isSelected: Bool,
        isLast: Bool,
        isEnabled: Bool
    ) {
        titleLabel.text = name
        subtitleLabel.text = subtitle
        lastIsSelected = isSelected && isEnabled
        checkmark.isHidden = !(isSelected && isEnabled)
        divider.isHidden = isLast
        refreshIconTile()

        contentView.alpha = isEnabled ? 1.0 : 0.45
        isUserInteractionEnabled = isEnabled
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        checkmark.isHidden = true
        divider.isHidden = false
        lastIsSelected = false
        contentView.alpha = 1.0
        isUserInteractionEnabled = true
    }
}
