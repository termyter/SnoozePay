import UIKit

// MARK: - Referral section cells
//
// Dedicated reusable cell classes for the three `.referral` rows. Previously
// each row was rebuilt as a `UITableViewCell(style:reuseIdentifier: nil)` on
// every `cellForRowAt:`, so UITableView could never recycle them and every
// `reloadData` (each `viewWillAppear`) accumulated fresh cell hierarchies (#203).

/// Row 1 — "Ваш код" + the user's 6-char code + copy glyph. Tap handling
/// stays in `didSelectRowAt:` so the whole row is the hit target.
final class ReferralMyCodeCell: UITableViewCell {

    static let reuseID = "ReferralMyCodeCell"

    private let codeLabel: UILabel = {
        let label = UILabel()
        label.font = AppTypography.moneySm
        label.textColor = AppColors.money500
        label.setContentHuggingPriority(.required, for: .horizontal)
        return label
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = AppColors.bg1

        let titleLabel = UILabel()
        titleLabel.text = "Ваш код"
        titleLabel.font = AppTypography.bodyLg
        titleLabel.textColor = AppColors.fg1

        let copyIcon = UIImageView(image: UIImage(systemName: "doc.on.clipboard"))
        copyIcon.tintColor = AppColors.fg3
        copyIcon.contentMode = .scaleAspectFit
        copyIcon.translatesAutoresizingMaskIntoConstraints = false
        copyIcon.widthAnchor.constraint(equalToConstant: 18).isActive = true
        copyIcon.heightAnchor.constraint(equalToConstant: 18).isActive = true

        let trailingStack = UIStackView(arrangedSubviews: [codeLabel, copyIcon])
        trailingStack.axis = .horizontal
        trailingStack.alignment = .center
        trailingStack.spacing = AppSpacing.sm

        let mainStack = UIStackView(arrangedSubviews: [titleLabel, trailingStack])
        mainStack.axis = .horizontal
        mainStack.alignment = .center
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: AppSpacing.lg
            ),
            mainStack.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -AppSpacing.lg
            ),
            mainStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(code: String) {
        codeLabel.text = code
    }
}

/// Row 2 — `SPInput` for the friend's code + "Применить" SPButton. The cell
/// owns the controls; the VC injects the text-field delegate and the apply
/// handler on each dequeue, and keeps a weak `friendCodeInput` reference for
/// inline validation messages (unchanged from the pre-reuse behaviour).
final class ReferralFriendInputCell: UITableViewCell {

    static let reuseID = "ReferralFriendInputCell"

    let input = SPInput(
        label: "Код друга",
        placeholder: "Введите 6 символов"
    )

    private let applyButton = SPButton(title: "Применить", variant: .money, size: .sm)

    /// Forwarded on every apply-button tap. Dropped in `prepareForReuse` so a
    /// recycled cell can't fire a stale owner's handler before reconfiguration.
    private var onApply: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = AppColors.bg1
        selectionStyle = .none

        input.textField.autocapitalizationType = .allCharacters
        input.textField.autocorrectionType = .no
        input.textField.returnKeyType = .done
        input.translatesAutoresizingMaskIntoConstraints = false

        applyButton.translatesAutoresizingMaskIntoConstraints = false
        applyButton.addTarget(self, action: #selector(applyTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [input, applyButton])
        stack.axis = .horizontal
        stack.alignment = .top
        stack.spacing = AppSpacing.sm
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: AppSpacing.lg
            ),
            stack.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -AppSpacing.lg
            ),
            stack.topAnchor.constraint(
                equalTo: contentView.topAnchor,
                constant: AppSpacing.md
            ),
            stack.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor,
                constant: -AppSpacing.md
            )
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// If the user has already redeemed a code, render it pre-filled and
    /// freeze further edits — the bonus is one-shot, and showing the code
    /// keeps support able to ask the user what they entered.
    func configure(
        appliedCode: String?,
        delegate: UITextFieldDelegate,
        onApply: @escaping () -> Void
    ) {
        input.textField.delegate = delegate
        self.onApply = onApply

        if let applied = appliedCode {
            input.textField.text = applied
            input.textField.isEnabled = false
            input.error = nil
            input.hint = "Код уже применён"
            applyButton.isEnabled = false
        } else {
            input.textField.isEnabled = true
            input.error = nil
            input.hint = nil
            applyButton.isEnabled = true
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onApply = nil
    }

    @objc private func applyTapped() {
        onApply?()
    }
}

/// Row 3 — small grey caption line. Modeled as a real cell rather than a
/// section footer so it inherits the card-row styling applied in `willDisplay`.
final class ReferralCaptionCell: UITableViewCell {

    static let reuseID = "ReferralCaptionCell"

    private let captionLabel: UILabel = {
        let label = UILabel()
        label.font = AppTypography.meta
        label.textColor = AppColors.fg3
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = AppColors.bg1
        selectionStyle = .none

        contentView.addSubview(captionLabel)
        NSLayoutConstraint.activate([
            captionLabel.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: AppSpacing.lg
            ),
            captionLabel.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -AppSpacing.lg
            ),
            captionLabel.topAnchor.constraint(
                equalTo: contentView.topAnchor,
                constant: AppSpacing.md
            ),
            captionLabel.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor,
                constant: -AppSpacing.md
            )
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(text: String) {
        captionLabel.text = text
    }
}
