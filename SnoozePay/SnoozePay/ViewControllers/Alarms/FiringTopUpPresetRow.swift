import UIKit

/// One existing firing top-up row, displaying the storefront's verbatim price.
/// Catalog updates reuse the labels and constraints; selection keeps the V2 tokens.
final class FiringTopUpPresetRow: UIControl {

    private let titleLabel = UILabel()
    private let hintLabel = UILabel()
    private let amountLabel = UILabel()
    private let checkChip = UIImageView()
    /// A known same-currency offer that does not cover one next charge is dimmed.
    private var insufficient: Bool

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
        displayPrice: String,
        selected: Bool,
        insufficient: Bool = false,
        onTap: @escaping () -> Void
    ) {
        self.insufficient = insufficient
        self.onTap = onTap
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setupUI()
        update(title: title, hint: hint, displayPrice: displayPrice, selected: selected, insufficient: insufficient)
        addTarget(self, action: #selector(handleTap), for: .touchUpInside)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        layer.cornerRadius = AppRadius.md      // 16pt
        layer.borderWidth = 1

        titleLabel.font = AppTypography.h4
        titleLabel.textColor = insufficient ? AppColors.fg3 : .white
        titleLabel.numberOfLines = 0

        hintLabel.font = AppTypography.meta
        hintLabel.textColor = AppColors.fg3
        hintLabel.numberOfLines = 0
        // A tier with no hint (price-free wording) must not reserve a line.

        // Preserve wrapping and the price/chip column's existing width priority.
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

    /// Catalog refresh only changes presentation, never rebuilds the row geometry.
    func update(title: String, hint: String, displayPrice: String, selected: Bool, insufficient: Bool) {
        self.insufficient = insufficient
        titleLabel.text = title
        titleLabel.textColor = insufficient ? AppColors.fg3 : .white
        hintLabel.text = hint
        hintLabel.isHidden = hint.isEmpty
        amountLabel.text = displayPrice
        isSelected = selected
        isAccessibilityElement = true
        accessibilityLabel = [title, displayPrice, hint].filter { !$0.isEmpty }.joined(separator: ", ")
        refreshSelection()
    }

    /// 22pt warn-gradient check chip shown on the selected row
    /// (`docs/design/snoozepay-2026-04-27/project/components/SPTopUp.jsx:163-169` contains "width: 22").
    /// Split out so the row's one-time setup remains small.
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
