import UIKit

/// V2 sticky header for the alarms list — title row + compact balance pill.
///
/// Layout (top → bottom):
/// ```
///  ┌────────────────────────────────────────────────────────┐
///  │ Будильники                                      ⊕(40)  │   <- title row
///  │ ┌────────────────────────────────────────────────────┐ │
///  │ │ [wallet]  БАЛАНС 840 ₽           [Пополнить]      │ │   <- pill
///  │ │           Хватит на ~16 откладываний              │ │
///  │ └────────────────────────────────────────────────────┘ │
///  └────────────────────────────────────────────────────────┘
///  ── 1pt whiteOverlay06 hairline ──
/// ```
///
/// Replaces the legacy big-balance-card + amber "БАЛАНС ПОЧТИ ПУСТ" banner —
/// the urgency is now folded directly into the pill: when balance drops below
/// `SPAlarmsListHeader.lowBalanceThreshold` the pill switches its background
/// to a soft warn tint + warn-stroke and the hint copy reflects the warning.
///
/// The 40×40 circular "+" button on the right is the only entry point for
/// "create new alarm" on this screen — the legacy nav-bar plus button is
/// suppressed by the host controller.
final class SPAlarmsListHeader: UIView {

    // MARK: - Public API

    /// Triggered when the user taps the "Пополнить" pill on the balance
    /// card. Kept named the same as the legacy header so the controller
    /// wiring doesn't need to change.
    var onBalanceTopUpTap: (() -> Void)?

    /// Triggered when the user taps the 40×40 "+" button. Distinct from
    /// `onBalanceTopUpTap` so the controller can route them to different
    /// flows (create-alarm vs top-up).
    var onAddTap: (() -> Void)?

    /// Kept for binary-compatibility with the legacy header — the V2
    /// pill folds the warning state into itself, so this callback now
    /// routes through the same "Пополнить" tap path.
    var onWarnTopUpTap: (() -> Void)?

    /// Update the balance pill in place. The pill auto-switches into its
    /// warn-tint variant when `balance.doubleValue ≤ lowBalanceThreshold`.
    /// `hint` and `delta` are accepted for source-compat with the legacy
    /// header; `delta` is currently ignored in the V2 pill layout (the
    /// rolling-week change rendered as `↑/↓ amount` migrates onto the
    /// Wallet screen). Pass through unchanged so existing call sites
    /// keep compiling.
    func setBalance(_ balance: Decimal, hint: String?, delta: Decimal? = nil) {
        _ = delta // accepted for API compat; pill omits the delta row.
        currentBalance = balance
        let isLow = (NSDecimalNumber(decimal: balance).doubleValue) <= Self.lowBalanceThreshold
        applyTone(isLow: isLow)
        balanceValueLabel.text = balance.formattedRubles()
        if let hint = hint, !hint.isEmpty {
            balanceHintLabel.text = hint
            balanceHintLabel.isHidden = false
        } else {
            balanceHintLabel.isHidden = true
        }
    }

    /// Kept for source-compat with the legacy header. The V2 pill folds
    /// the warning into its own tone, so this method now just routes the
    /// state through `setBalance(_:hint:)`'s low-balance branch — the
    /// controller already calls both methods on refresh.
    func setWarning(visible: Bool, balance: Decimal) {
        // `applyTone` is driven by `setBalance`; this method is preserved
        // so the controller doesn't need to be rewritten to drop the
        // call. The `visible` flag is implied by the balance value.
        _ = (visible, balance)
    }

    // MARK: - Tokens

    /// Pill bg switches to warn-tint at or below this threshold (₽).
    /// Matches `AlarmsListViewModel.lowBalanceThreshold` so the view and
    /// the model agree on what "low" means without coupling them through
    /// an import.
    static let lowBalanceThreshold: Double = 100

    // MARK: - Subviews

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        // h1 32pt extrabold with -0.02em kerning per `tokens.css` L80.
        label.font = AppTypography.h1
        label.textColor = AppColors.fg1
        label.attributedText = NSAttributedString(
            string: "Будильники",
            attributes: [
                .font: AppTypography.h1,
                .kern: -32 * 0.01, // ~ -0.32 — matches `letterSpacing: -.02em` doubled-down
                .foregroundColor: AppColors.fg1
            ]
        )
        return label
    }()

    private let addButton: UIControl = {
        let view = UIControl()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 20
        view.layer.masksToBounds = false
        // Money-tinted drop shadow — matches `--sp-shadow-money`.
        view.layer.shadowColor = AppColors.money500.cgColor
        view.layer.shadowOpacity = 0.35
        view.layer.shadowRadius = 14
        view.layer.shadowOffset = CGSize(width: 0, height: 6)
        return view
    }()

    /// Gradient layer sits behind the plus glyph inside `addButton`.
    private let addButtonGradient: SPGradientView = {
        let view = SPGradientView(
            colors: SPSupport.moneyGradientColors,
            locations: SPSupport.moneyGradientLocations
        )
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isUserInteractionEnabled = false
        view.layer.cornerRadius = 20
        view.layer.masksToBounds = true
        return view
    }()

    private let addIconView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFit
        view.tintColor = AppColors.fgOnMoney
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)
        view.image = UIImage(systemName: "plus", withConfiguration: config)
        view.isUserInteractionEnabled = false
        return view
    }()

    private let pillButton: UIControl = {
        let view = UIControl()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 14
        view.layer.masksToBounds = true
        view.layer.borderWidth = 1
        return view
    }()

    /// Money-gradient 40×40 rounded square left of the balance text.
    private let walletIconHost: SPGradientView = {
        let view = SPGradientView(
            colors: SPSupport.moneyGradientColors,
            locations: SPSupport.moneyGradientLocations
        )
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 10
        view.layer.masksToBounds = true
        view.isUserInteractionEnabled = false
        return view
    }()

    private let walletIconImageView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFit
        view.tintColor = AppColors.fgOnMoney
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        view.image = UIImage(systemName: "creditcard.fill", withConfiguration: config)
        return view
    }()

    private let balanceCapsLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.attributedText = NSAttributedString(
            string: "БАЛАНС",
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: AppColors.fg3
            ]
        )
        return label
    }()

    private let balanceValueLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        // 20pt mono bold — `moneyMd`. Tabular nums via the mono font.
        label.font = AppTypography.moneyMd
        label.textColor = AppColors.fg1
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.6
        label.numberOfLines = 1
        return label
    }()

    private let balanceHintLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = AppTypography.meta
        label.textColor = AppColors.fg3
        label.numberOfLines = 1
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.8
        return label
    }()

    private let topUpButton = SPButton(
        title: "Пополнить",
        variant: .money,
        size: .sm
    )

    private let bottomHairline: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = AppColors.whiteOverlay06
        return view
    }()

    // MARK: - State

    private var currentBalance: Decimal = 0

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: SPAlarmsListHeader, _) in
                view.refreshDynamicColors()
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
        refreshDynamicColors()
    }

    private func refreshDynamicColors() {
        // CALayer cgColors don't auto-resolve dynamic UIColors.
        bottomHairline.backgroundColor = AppColors.whiteOverlay06
        let isLow = NSDecimalNumber(decimal: currentBalance).doubleValue <= Self.lowBalanceThreshold
        applyTone(isLow: isLow)
    }

    // MARK: - Configuration

    // swiftlint:disable:next function_body_length
    private func configure() {
        backgroundColor = AppColors.bg0

        addSubview(titleLabel)
        addSubview(addButton)
        addButton.addSubview(addButtonGradient)
        addButton.addSubview(addIconView)

        addSubview(pillButton)
        pillButton.addSubview(walletIconHost)
        walletIconHost.addSubview(walletIconImageView)
        pillButton.addSubview(balanceCapsLabel)
        pillButton.addSubview(balanceValueLabel)
        pillButton.addSubview(balanceHintLabel)
        pillButton.addSubview(topUpButton)
        topUpButton.translatesAutoresizingMaskIntoConstraints = false
        topUpButton.isUserInteractionEnabled = true

        addSubview(bottomHairline)

        addButton.addTarget(self, action: #selector(addTapped), for: .touchUpInside)
        pillButton.addTarget(self, action: #selector(pillTapped), for: .touchUpInside)
        topUpButton.addTarget(self, action: #selector(topUpTapped), for: .touchUpInside)

        let inset = AppSpacing.screenInset

        NSLayoutConstraint.activate([
            // ── Title row ─────────────────────────────────────────────
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: AppSpacing.sp2),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            titleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: addButton.leadingAnchor,
                constant: -AppSpacing.sp3
            ),

            addButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            addButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            addButton.widthAnchor.constraint(equalToConstant: 40),
            addButton.heightAnchor.constraint(equalToConstant: 40),

            addButtonGradient.topAnchor.constraint(equalTo: addButton.topAnchor),
            addButtonGradient.leadingAnchor.constraint(equalTo: addButton.leadingAnchor),
            addButtonGradient.trailingAnchor.constraint(equalTo: addButton.trailingAnchor),
            addButtonGradient.bottomAnchor.constraint(equalTo: addButton.bottomAnchor),

            addIconView.centerXAnchor.constraint(equalTo: addButton.centerXAnchor),
            addIconView.centerYAnchor.constraint(equalTo: addButton.centerYAnchor),

            // ── Balance pill ──────────────────────────────────────────
            pillButton.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: AppSpacing.sp3),
            pillButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            pillButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            pillButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -AppSpacing.sp4),

            // Wallet icon — 40×40 leading.
            walletIconHost.leadingAnchor.constraint(equalTo: pillButton.leadingAnchor, constant: 12),
            walletIconHost.centerYAnchor.constraint(equalTo: pillButton.centerYAnchor),
            walletIconHost.widthAnchor.constraint(equalToConstant: 40),
            walletIconHost.heightAnchor.constraint(equalToConstant: 40),

            walletIconImageView.centerXAnchor.constraint(equalTo: walletIconHost.centerXAnchor),
            walletIconImageView.centerYAnchor.constraint(equalTo: walletIconHost.centerYAnchor),

            // Top-up button — sm, trailing.
            topUpButton.trailingAnchor.constraint(equalTo: pillButton.trailingAnchor, constant: -12),
            topUpButton.centerYAnchor.constraint(equalTo: pillButton.centerYAnchor),

            // Balance value row — baseline-aligned caps "БАЛАНС" + amount.
            balanceCapsLabel.leadingAnchor.constraint(
                equalTo: walletIconHost.trailingAnchor,
                constant: AppSpacing.sp3
            ),
            balanceCapsLabel.topAnchor.constraint(equalTo: pillButton.topAnchor, constant: 12),

            balanceValueLabel.leadingAnchor.constraint(
                equalTo: balanceCapsLabel.trailingAnchor,
                constant: AppSpacing.sp2
            ),
            balanceValueLabel.firstBaselineAnchor.constraint(equalTo: balanceCapsLabel.firstBaselineAnchor),
            balanceValueLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: topUpButton.leadingAnchor,
                constant: -AppSpacing.sp3
            ),

            // Meta hint — below the value row.
            balanceHintLabel.leadingAnchor.constraint(
                equalTo: walletIconHost.trailingAnchor,
                constant: AppSpacing.sp3
            ),
            balanceHintLabel.topAnchor.constraint(equalTo: balanceValueLabel.bottomAnchor, constant: 2),
            balanceHintLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: topUpButton.leadingAnchor,
                constant: -AppSpacing.sp3
            ),
            balanceHintLabel.bottomAnchor.constraint(
                lessThanOrEqualTo: pillButton.bottomAnchor,
                constant: -12
            ),

            // ── Bottom hairline ───────────────────────────────────────
            bottomHairline.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomHairline.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomHairline.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomHairline.heightAnchor.constraint(equalToConstant: 1)
        ])

        applyTone(isLow: false)
    }

    /// Switch the pill chrome between the neutral (bg2 + whiteOverlay08
    /// stroke) and warn (warn500@12% + warn500@45% stroke) variants. The
    /// hint copy + colour also shift so the low-balance state stays legible
    /// at a glance without an extra banner row.
    private func applyTone(isLow: Bool) {
        if isLow {
            pillButton.backgroundColor = AppColors.warn500.withAlphaComponent(0.12)
            pillButton.layer.borderColor = AppColors.warn500.withAlphaComponent(0.45).cgColor
            balanceHintLabel.textColor = AppColors.warn300
        } else {
            pillButton.backgroundColor = AppColors.bg2
            pillButton.layer.borderColor = AppColors.whiteOverlay08.cgColor
            balanceHintLabel.textColor = AppColors.fg3
        }
    }

    // MARK: - Actions

    @objc private func addTapped() {
        SPSupport.animatePress(addButton, pressed: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + SPSupport.durationQuick) { [weak self] in
            guard let self else { return }
            SPSupport.animatePress(self.addButton, pressed: false)
        }
        onAddTap?()
    }

    @objc private func pillTapped() {
        // Tapping the body of the pill (anywhere except the explicit
        // "Пополнить" CTA) is a shortcut to the same destination — keeps
        // the surface "all top-up" instead of forcing the user to hit a
        // small button.
        onBalanceTopUpTap?()
        onWarnTopUpTap?()
    }

    @objc private func topUpTapped() {
        onBalanceTopUpTap?()
        onWarnTopUpTap?()
    }
}
