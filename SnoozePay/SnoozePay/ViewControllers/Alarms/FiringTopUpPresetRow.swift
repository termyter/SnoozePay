import UIKit

/// One full-width top-up preset row in the firing top-up sheet.
///
/// Spec — `SPTopUp.jsx:148-170`: a 16×20-padded, 16pt-radius row with a title
/// (h4) + hint (meta) on the left and the rouble amount (money-md) + a 22pt
/// warn-gradient check chip on the right. Title and hint are computed by
/// `FiringTopUpCopy` from the live snooze price (#548) — the comp's literal
/// «+1 откладывание · ровно на сейчас» was true only at exactly 149 ₽. Selected
/// rows gain a warn400 border + a faint warn .08 wash and tint the amount
/// warn400; unselected rows use a white08 hairline over a white04 fill.
///
/// The displayed amount is passed in by the sheet and is always the SKU's
/// catalogue amount (#297) — this view never invents a number, it just renders
/// what it's given.
final class FiringTopUpPresetRow: UIControl {

    private let titleLabel = UILabel()
    private let hintLabel = UILabel()
    private let amountLabel = UILabel()
    private let checkChip = UIImageView()
    private let amount: Int
    /// `true` when this tier does not buy a single snooze at the current price
    /// (#548). Marked rather than hidden — the user may still want the money in
    /// the wallet — so the row dims its title and drops the warn tint on the
    /// amount, and the title itself spells out «Не хватит на откладывание».
    private let insufficient: Bool

    private let onTap: () -> Void

    override var isSelected: Bool {
        didSet { refreshSelection() }
    }

    override var isHighlighted: Bool {
        didSet { SPSupport.animatePress(self, pressed: isHighlighted) }
    }

    init(
        title: String,
        hint: String,
        amount: Int,
        selected: Bool,
        insufficient: Bool = false,
        onTap: @escaping () -> Void
    ) {
        self.amount = amount
        self.insufficient = insufficient
        self.onTap = onTap
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        configure(title: title, hint: hint)
        isSelected = selected
        refreshSelection()
        addTarget(self, action: #selector(handleTap), for: .touchUpInside)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure(title: String, hint: String) {
        layer.cornerRadius = AppRadius.md      // 16pt
        layer.borderWidth = 1

        titleLabel.text = title
        titleLabel.font = AppTypography.h4
        titleLabel.textColor = insufficient ? AppColors.fg3 : .white
        titleLabel.numberOfLines = 0

        hintLabel.text = hint
        hintLabel.font = AppTypography.meta
        hintLabel.textColor = AppColors.fg3
        hintLabel.numberOfLines = 0
        // A tier with no hint (price-free wording) must not reserve a line.
        hintLabel.isHidden = hint.isEmpty

        // Derived copy is longer than the old comp literals («Не хватит на
        // откладывание» vs «+1 откладывание»), so the left column wraps instead
        // of shoving the amount off the row: the amount + chip win the width
        // fight, the text takes a second line and the ≥60pt row grows.
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        hintLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        amountLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let leftStack = UIStackView(arrangedSubviews: [titleLabel, hintLabel])
        leftStack.axis = .vertical
        leftStack.spacing = 2
        leftStack.alignment = .leading
        leftStack.isUserInteractionEnabled = false
        leftStack.translatesAutoresizingMaskIntoConstraints = false

        amountLabel.font = AppTypography.moneyMd
        amountLabel.translatesAutoresizingMaskIntoConstraints = false
        amountLabel.text = MoneyFormatter.string(amount)

        configureCheckChip()

        let rightStack = UIStackView(arrangedSubviews: [amountLabel, checkChip])
        rightStack.axis = .horizontal
        rightStack.spacing = AppSpacing.sp2
        rightStack.alignment = .center
        rightStack.isUserInteractionEnabled = false
        rightStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(leftStack)
        addSubview(rightStack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 60),
            leftStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: AppSpacing.sp5),
            leftStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            leftStack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: AppSpacing.sp4),
            leftStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -AppSpacing.sp4),

            rightStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -AppSpacing.sp5),
            rightStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            rightStack.leadingAnchor.constraint(
                greaterThanOrEqualTo: leftStack.trailingAnchor,
                constant: AppSpacing.sp3
            ),

            checkChip.widthAnchor.constraint(equalToConstant: 22),
            checkChip.heightAnchor.constraint(equalToConstant: 22)
        ])
    }

    /// 22pt warn-gradient check chip shown on the selected row
    /// (`SPTopUp.jsx:163-169`). Split out of `configure` to keep that method
    /// under the linter's body-length threshold once the derived copy (#548)
    /// added its own label setup.
    private func configureCheckChip() {
        let configuration = UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        checkChip.image = UIImage(systemName: "checkmark", withConfiguration: configuration)?
            .withRenderingMode(.alwaysTemplate)
        checkChip.tintColor = AppColors.fgOnWarn
        checkChip.backgroundColor = AppColors.warnFill500
        checkChip.contentMode = .center
        checkChip.layer.cornerRadius = 11
        checkChip.layer.masksToBounds = true
        checkChip.translatesAutoresizingMaskIntoConstraints = false
    }

    private func refreshSelection() {
        if isSelected {
            backgroundColor = AppColors.warnFill500.withAlphaComponent(0.08)
            layer.borderColor = AppColors.warn400.cgColor
            amountLabel.textColor = AppColors.warn400
            checkChip.isHidden = false
        } else {
            backgroundColor = AppColors.whiteOverlay04
            layer.borderColor = AppColors.whiteOverlay08.cgColor
            // Dim the amount of a tier that buys no snooze so the row reads as
            // "possible, but not what you're here for" (#548).
            amountLabel.textColor = insufficient ? AppColors.fg3 : .white
            checkChip.isHidden = true
        }
    }

    @objc private func handleTap() {
        onTap()
    }
}
