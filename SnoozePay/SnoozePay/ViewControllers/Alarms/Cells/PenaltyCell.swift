import UIKit

/// V2 "Цена откладывания" preset row: 5 fixed-price chips (20 / 50 / 100 /
/// 200 / 500) — replaces the prior 10...1000 slider so the user picks from
/// the design's curated price ladder rather than landing on noisy values.
///
/// Layout follows `SPScreensV2.jsx` lines 594-615 — the selected chip wears
/// the warn gradient (`fgOnWarn` text) and unselected chips read as the
/// `whiteOverlay06` muted state. The active amount is mirrored in the cell's
/// trailing accessory label so the host card's "right side" still surfaces
/// the live amount alongside the chip selection.
final class PenaltyCell: UITableViewCell {

    static let reuseID = "PenaltyCell"

    /// V2 preset ladder. Tweak in lock-step with the JSX spec — these are
    /// the only values the picker exposes.
    static let presets: [Double] = [20, 50, 100, 200, 500]

    // MARK: - UI

    /// Mono-font live "{N} ₽" label sitting above the chip row — pulls the
    /// "ЦЕНА ОТКЛАДЫВАНИЯ" caps from the section header and uses the
    /// `moneyMd` typography role tinted `warn400`.
    private let valueLabel: UILabel = {
        let label = UILabel()
        label.font = AppTypography.moneyMd
        label.textColor = AppColors.warn400
        label.textAlignment = .right
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

    // MARK: - Callbacks

    /// Fires when the user picks a new preset.
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

        contentView.addSubview(valueLabel)
        contentView.addSubview(presetStack)

        NSLayoutConstraint.activate([
            valueLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -AppSpacing.lg),
            valueLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: AppSpacing.sm),

            presetStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: AppSpacing.lg),
            presetStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -AppSpacing.lg),
            presetStack.topAnchor.constraint(equalTo: valueLabel.bottomAnchor, constant: AppSpacing.sm),
            presetStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -AppSpacing.md)
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onValueChanged = nil
    }

    // MARK: - Configure

    func configure(amount: Double) {
        currentAmount = amount
        valueLabel.text = "\(Int(amount)) ₽"
        refreshAppearance()
    }

    // MARK: - Appearance

    /// Re-paint each chip according to the current selection. CALayer cgColor
    /// properties don't auto-resolve dynamic UIColors, so this also runs on
    /// theme flips.
    private func refreshAppearance() {
        for (index, button) in presetButtons.enumerated() {
            let preset = Self.presets[index]
            let isOn = abs(preset - currentAmount) < .ulpOfOne
            if isOn {
                button.backgroundColor = AppColors.warn500
                button.setTitleColor(AppColors.fgOnWarn, for: .normal)
                button.layer.borderWidth = 0
            } else {
                button.backgroundColor = AppColors.whiteOverlay06
                button.setTitleColor(AppColors.fg2, for: .normal)
                button.layer.borderWidth = 0
            }
        }
    }

    // MARK: - Actions

    @objc private func presetTapped(_ sender: UIButton) {
        guard let index = presetButtons.firstIndex(of: sender) else { return }
        let amount = Self.presets[index]
        UISelectionFeedbackGenerator().selectionChanged()
        configure(amount: amount)
        onValueChanged?(amount)
    }
}
