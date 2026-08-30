import UIKit

/// V3 «Цена откладывания» card (#230, `SPComponents.jsx` `SnoozePriceCard`):
/// a large free-numeric field (mono 32pt, amber, trailing ₽) over the curated
/// quick-chip ladder. Replaces the chips-only V2 picker — the design now lets
/// the user type any whole price ≥ 1 ₽ (no maximum, chat3) while the chips stay
/// as fast presets and highlight when they match the typed value.
///
/// Validation: a whole number ≥ 1. Empty / zero / invalid input surfaces the
/// red «Минимум 1 ₽» helper and is NOT committed — on end-editing the field
/// reverts to the last valid amount, so the model never sees a bad price.
final class PenaltyCell: UITableViewCell {

    static let reuseID = "PenaltyCell"

    /// Quick-chip ladder. Tap fills the field; a chip matching the current
    /// value lights amber.
    static let presets: [Double] = [20, 50, 100, 200, 500]

    /// Floor enforced on the free input (chat3: «Минимум — 1 ₽, максимума нет»).
    static let minimumAmount = 1

    // MARK: - UI

    private let captionLabel: UILabel = {
        let label = UILabel()
        label.attributedText = NSAttributedString(
            string: Localized.text("create_alarm.penalty.caps").uppercased(),
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: AppColors.fg3
            ]
        )
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let hintLabel: UILabel = {
        let label = UILabel()
        label.text = Localized.text("create_alarm.penalty.hint")
        label.font = AppTypography.meta
        label.textColor = AppColors.fg3
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    /// Big editable mono amount — `moneyXl`-scale (32pt) amber, numeric pad.
    private let amountField: UITextField = {
        let field = UITextField()
        field.font = AppFonts.mono(.bold, 32)
        field.textColor = AppColors.priceDisplay
        field.tintColor = AppColors.priceDisplay
        field.keyboardType = .numberPad
        field.borderStyle = .none
        field.setContentHuggingPriority(.required, for: .horizontal)
        field.setContentCompressionResistancePriority(.required, for: .horizontal)
        field.accessibilityLabel = Localized.text("create_alarm.penalty.accessibility")
        field.accessibilityIdentifier = "createAlarm.penaltyField"
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }()

    /// «Готово» toolbar above the numberPad — the pad has no return key, so this
    /// is the explicit dismissal path (#410). Complements the table's
    /// interactive drag-to-dismiss.
    private lazy var accessoryToolbar: UIToolbar = {
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        let spacer = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let done = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneTapped))
        done.accessibilityIdentifier = "createAlarm.penaltyDone"
        toolbar.items = [spacer, done]
        return toolbar
    }()

    /// Trailing ₽ in the same mono amber as the number.
    private let suffixLabel: UILabel = {
        let label = UILabel()
        label.text = "₽"
        label.font = AppFonts.mono(.bold, 32)
        label.textColor = AppColors.warn400
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    /// Red «Минимум 1 ₽» helper — hidden unless the field holds invalid input.
    private let helperLabel: UILabel = {
        let label = UILabel()
        label.text = Localized.text("create_alarm.penalty.minimum")
        label.font = AppTypography.meta
        label.textColor = AppColors.pain400
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let presetStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = AppSpacing.sp2
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private var presetButtons: [UIButton] = []
    private var currentAmount: Double = 0
    /// Last value that passed validation — restored if the field is left blank.
    private var lastValidAmount: Double = Double(PenaltyCell.minimumAmount)

    // MARK: - Callbacks

    /// Fires with a validated whole amount (≥ 1 ₽) when the user types a valid
    /// value or taps a chip. Invalid input never fires it.
    var onValueChanged: ((Double) -> Void)?

    // MARK: - Init

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: PenaltyCell, _) in
                view.refreshAppearance()
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @available(iOS, deprecated: 17.0, message: "Replaced by registerForTraitChanges; kept for iOS 15/16.")
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if #available(iOS 17.0, *) { return }
        refreshAppearance()
    }

    // MARK: - Setup

    private func setupUI() {
        backgroundColor = AppColors.bg1
        selectionStyle = .none

        amountField.inputAccessoryView = accessoryToolbar
        amountField.addTarget(self, action: #selector(amountEditingChanged), for: .editingChanged)
        amountField.addTarget(self, action: #selector(amountEditingEnded), for: .editingDidEnd)

        for amount in Self.presets {
            let button = UIButton(type: .system)
            button.setTitle(String(Int(amount)), for: .normal)
            button.titleLabel?.font = AppFonts.mono(.semibold, 14)
            button.layer.cornerRadius = AppRadius.sm
            button.layer.masksToBounds = true
            button.addTarget(self, action: #selector(presetTapped(_:)), for: .touchUpInside)
            button.heightAnchor.constraint(equalToConstant: 40).isActive = true
            presetButtons.append(button)
            presetStack.addArrangedSubview(button)
        }

        // Amount + ₽, left-aligned with a flexible trailing spacer.
        let amountSpacer = UIView()
        amountSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let amountRow = UIStackView(arrangedSubviews: [amountField, suffixLabel, amountSpacer])
        amountRow.axis = .horizontal
        amountRow.alignment = .firstBaseline
        amountRow.spacing = AppSpacing.sp1

        let column = UIStackView(arrangedSubviews: [
            captionLabel, hintLabel, amountRow, helperLabel, presetStack
        ])
        column.axis = .vertical
        column.spacing = AppSpacing.sp2
        column.setCustomSpacing(AppSpacing.sp3, after: hintLabel)
        column.setCustomSpacing(AppSpacing.sp3, after: helperLabel)
        column.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(column)

        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: AppSpacing.sp5),
            column.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -AppSpacing.sp5),
            column.topAnchor.constraint(equalTo: contentView.topAnchor, constant: AppSpacing.sm),
            column.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -AppSpacing.md)
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onValueChanged = nil
    }

    // MARK: - Configure

    func configure(amount: Double) {
        let whole = max(Int(amount.rounded()), Self.minimumAmount)
        currentAmount = Double(whole)
        lastValidAmount = currentAmount
        amountField.text = String(whole)
        setHelper(visible: false)
        refreshAppearance()
    }

    // MARK: - Validation

    /// Parse the field as a whole ₽ amount ≥ minimum. Returns nil for empty /
    /// zero / non-numeric input.
    private func validatedAmount() -> Int? {
        guard let text = amountField.text, let value = Int(text), value >= Self.minimumAmount else {
            return nil
        }
        return value
    }

    /// Live keystroke handler — updates ONLY the cell's own appearance (helper
    /// flag + chip highlight). It does NOT commit to the model: typing "100"
    /// must not push 1→10→100 and flicker the preset chips / progressive chain
    /// downstream (#410). The commit happens once on `.editingDidEnd`.
    @objc private func amountEditingChanged() {
        guard let value = validatedAmount() else {
            setHelper(visible: true)
            return
        }
        setHelper(visible: false)
        currentAmount = Double(value)
        refreshAppearance()
    }

    @objc private func amountEditingEnded() {
        guard let value = validatedAmount() else {
            // Left blank / invalid — revert to the last valid amount.
            amountField.text = String(Int(lastValidAmount))
            currentAmount = lastValidAmount
            setHelper(visible: false)
            refreshAppearance()
            return
        }
        setHelper(visible: false)
        currentAmount = Double(value)
        // Commit only the final value once editing ends.
        guard abs(lastValidAmount - currentAmount) >= .ulpOfOne else { return }
        lastValidAmount = currentAmount
        refreshAppearance()
        onValueChanged?(currentAmount)
    }

    @objc private func doneTapped() {
        amountField.resignFirstResponder()
    }

    private func setHelper(visible: Bool) {
        helperLabel.isHidden = !visible
        amountField.textColor = visible ? AppColors.pain400 : AppColors.priceDisplay
        suffixLabel.textColor = visible ? AppColors.pain400 : AppColors.priceDisplay
    }

    // MARK: - Appearance

    /// Re-paint each chip according to the current selection. CALayer cgColor
    /// properties don't auto-resolve dynamic UIColors, so this also runs on
    /// theme flips.
    private func refreshAppearance() {
        for (index, button) in presetButtons.enumerated() {
            let preset = Self.presets[index]
            let isOn = abs(preset - currentAmount) < .ulpOfOne
            button.backgroundColor = isOn ? AppColors.warnFill500 : AppColors.whiteOverlay06
            button.setTitleColor(isOn ? AppColors.fgOnWarn : AppColors.fg2, for: .normal)
            button.layer.borderWidth = 0
        }
    }

    // MARK: - Actions

    @objc private func presetTapped(_ sender: UIButton) {
        guard let index = presetButtons.firstIndex(of: sender) else { return }
        let amount = Self.presets[index]
        UISelectionFeedbackGenerator().selectionChanged()
        amountField.text = String(Int(amount))
        currentAmount = amount
        lastValidAmount = amount
        setHelper(visible: false)
        refreshAppearance()
        onValueChanged?(amount)
    }
}
