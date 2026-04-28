import UIKit

/// Single-sound row used by `SoundPickerViewController` (#150 design refresh).
///
/// Layout: leading `SPButton(.quiet, .sm)` toggling between play / pause →
/// title (bodyLg) + duration (meta) text stack → trailing checkmark on the
/// selected row. The whole content is wrapped in a hand-rolled card surface
/// — `SPCard` itself doesn't expose a "selected" state, so we render the
/// money-tinted border + `whiteOverlay06` fill directly on a plain `UIView`
/// container so the picker can animate selection without re-instantiating
/// the card every reload.
final class SoundPickerRowCell: UITableViewCell {

    static let reuseID = "SoundPickerRowCell"

    var onPlayTapped: (() -> Void)?

    // MARK: - UI

    private let cardContainer = UIView()
    private var playButton = SPButton(
        title: "",
        variant: .quiet,
        size: .sm,
        icon: UIImage(systemName: "play.fill")
    )

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = AppTypography.bodyLg
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
            UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        )
        view.tintColor = AppColors.money500
        view.translatesAutoresizingMaskIntoConstraints = false
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

    // MARK: - Init

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
        // iOS 17 deprecated `traitCollectionDidChange(_:)` — register a
        // closure-based observer when available; the legacy override below
        // remains as a fallback for older runtimes.
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: SoundPickerRowCell, _) in
                view.refreshChromeColors()
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

        cardContainer.translatesAutoresizingMaskIntoConstraints = false
        cardContainer.layer.cornerRadius = AppRadius.md
        cardContainer.layer.masksToBounds = false
        contentView.addSubview(cardContainer)

        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(subtitleLabel)

        playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)

        cardContainer.addSubview(playButton)
        cardContainer.addSubview(textStack)
        cardContainer.addSubview(checkmark)

        let cardInset = AppSpacing.sp3
        let verticalPadding = AppSpacing.sp3
        NSLayoutConstraint.activate([
            cardContainer.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            cardContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            cardContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            playButton.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor, constant: cardInset),
            playButton.centerYAnchor.constraint(equalTo: cardContainer.centerYAnchor),
            playButton.widthAnchor.constraint(equalToConstant: 44),

            textStack.leadingAnchor.constraint(equalTo: playButton.trailingAnchor, constant: AppSpacing.sp3),
            textStack.centerYAnchor.constraint(equalTo: cardContainer.centerYAnchor),
            textStack.topAnchor.constraint(
                greaterThanOrEqualTo: cardContainer.topAnchor, constant: verticalPadding
            ),
            textStack.bottomAnchor.constraint(
                lessThanOrEqualTo: cardContainer.bottomAnchor, constant: -verticalPadding
            ),

            checkmark.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor, constant: -cardInset),
            checkmark.centerYAnchor.constraint(equalTo: cardContainer.centerYAnchor),
            checkmark.widthAnchor.constraint(equalToConstant: 20),

            textStack.trailingAnchor.constraint(
                lessThanOrEqualTo: checkmark.leadingAnchor, constant: -AppSpacing.sp3
            ),
            cardContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 56)
        ])
    }

    @available(iOS, deprecated: 17.0, message: "Replaced by registerForTraitChanges; kept for iOS 15/16.")
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        // iOS 17+ runtimes get the refresh through the registered observer
        // (see init); skip here so we don't refresh twice.
        if #available(iOS 17.0, *) { return }
        // CALayer cgColor doesn't auto-resolve dynamic UIColors — refresh
        // border / shadow on system theme flips.
        refreshChromeColors()
    }

    private func refreshChromeColors() {
        let scale = max(traitCollection.displayScale, 1)
        if lastIsSelected {
            cardContainer.backgroundColor = AppColors.whiteOverlay06
            cardContainer.layer.borderWidth = 1.0 / scale
            cardContainer.layer.borderColor = AppColors.strokeMoney
                .resolvedColor(with: traitCollection).cgColor
            cardContainer.layer.shadowColor = AppColors.money500.cgColor
            cardContainer.layer.shadowOpacity = traitCollection.userInterfaceStyle == .light ? 0.15 : 0.2
            cardContainer.layer.shadowRadius = 8
            cardContainer.layer.shadowOffset = CGSize(width: 0, height: 4)
        } else {
            cardContainer.backgroundColor = AppColors.bg1
            cardContainer.layer.borderWidth = 1.0 / scale
            cardContainer.layer.borderColor = AppColors.stroke1
                .resolvedColor(with: traitCollection).cgColor
            cardContainer.layer.shadowOpacity = 0
        }
    }

    // MARK: - Configure

    func configure(name: String, duration: String, isSelected: Bool, isPlaying: Bool) {
        titleLabel.text = name
        subtitleLabel.text = duration
        checkmark.isHidden = !isSelected
        lastIsSelected = isSelected
        refreshChromeColors()

        // Replace the SPButton's icon by rebuilding it — `SPButton` doesn't
        // expose a setter for the leading icon and we want the play / pause
        // toggle to read with the system "play.fill" / "pause.fill" SF
        // symbols at consistent weight. Cheaper than animating into a
        // CAShapeLayer.
        playButton.removeFromSuperview()
        playButton.removeTarget(self, action: nil, for: .allEvents)
        let newIcon = UIImage(systemName: isPlaying ? "pause.fill" : "play.fill")
        let replacement = SPButton(
            title: "",
            variant: .quiet,
            size: .sm,
            icon: newIcon
        )
        replacement.translatesAutoresizingMaskIntoConstraints = false
        replacement.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        cardContainer.addSubview(replacement)
        NSLayoutConstraint.activate([
            replacement.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor, constant: AppSpacing.sp3),
            replacement.centerYAnchor.constraint(equalTo: cardContainer.centerYAnchor),
            replacement.widthAnchor.constraint(equalToConstant: 44)
        ])
        playButton = replacement

        // Re-pin the text stack leading anchor because we just swapped the
        // play button view it depends on. AutoLayout keeps the old (deleted)
        // constraint dangling otherwise.
        for constraint in cardContainer.constraints
        where constraint.firstItem === textStack && constraint.firstAttribute == .leading {
            cardContainer.removeConstraint(constraint)
        }
        textStack.leadingAnchor.constraint(
            equalTo: playButton.trailingAnchor, constant: AppSpacing.sp3
        ).isActive = true
    }

    @objc private func playTapped() {
        onPlayTapped?()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onPlayTapped = nil
        checkmark.isHidden = true
        lastIsSelected = false
    }
}
