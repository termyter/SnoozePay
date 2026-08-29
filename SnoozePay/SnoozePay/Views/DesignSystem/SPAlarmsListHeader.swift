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
/// Replaces the legacy big-balance-card + amber «БАЛАНС ПОЧТИ ПУСТ» banner —
/// the urgency is now folded directly into the pill: when balance drops below
/// `SPAlarmsListHeader.lowBalanceThreshold` the pill switches its background
/// to a soft warn tint + warn-stroke and the hint copy reflects the warning.
/// At exactly 0 ₽ the pill escalates further into the pain (zero-balance)
/// variant — red stroke, reddish gradient wash, crossed-out coin tile and an
/// amount in the pain-wash ink (#232); the «Пополнить» CTA stays money-green
/// throughout.
///
/// Both tinted tones ink their text with the `fgOn*Wash` pair rather than the
/// bright `*300` step: a wash is not a fill, and on the light theme's pale
/// tint `warn300` / `pain300` measure 2.70:1 / 2.77:1 (#491).
///
/// The 40×40 circular "+" button on the right is the only entry point for
/// "create new alarm" on this screen — the legacy nav-bar plus button is
/// suppressed by the host controller.
final class SPAlarmsListHeader: UIView {

    // MARK: - Public API

    /// Triggered when the user taps the «Пополнить» pill on the balance
    /// card. Kept named the same as the legacy header so the controller
    /// wiring doesn't need to change.
    var onBalanceTopUpTap: (() -> Void)?

    /// Triggered when the user taps the 40×40 "+" button. Distinct from
    /// `onBalanceTopUpTap` so the controller can route them to different
    /// flows (create-alarm vs top-up).
    var onAddTap: (() -> Void)?

    /// Triggered when the user taps the 40×40 gear button. The settings
    /// affordance now lives inside the header title row (left of the money
    /// "+"), so the host controller can hide the system nav bar entirely on
    /// this tab (SPScreensV2.jsx L316-333).
    var onSettingsTap: (() -> Void)?

    /// Kept for binary-compatibility with the legacy header — the V2
    /// pill folds the warning state into itself, so this callback now
    /// routes through the same «Пополнить» tap path.
    var onWarnTopUpTap: (() -> Void)?

    /// Update the balance pill in place. The pill auto-switches between
    /// three tones based on the amount: pain when the balance is 0 ₽
    /// (zero-balance state, #232), warn-tint when
    /// `balance.doubleValue ≤ lowBalanceThreshold`, neutral otherwise.
    /// `hint` and `delta` are accepted for source-compat with the legacy
    /// header; `delta` is currently ignored in the V2 pill layout (the
    /// rolling-week change rendered as `↑/↓ amount` migrates onto the
    /// Wallet screen). Pass through unchanged so existing call sites
    /// keep compiling.
    func setBalance(_ balance: Decimal, hint: String?, delta: Decimal? = nil) {
        _ = delta // accepted for API compat; pill omits the delta row.
        currentBalance = balance
        hasBalance = true
        // The amount's ink is part of the tone (0 ₽ renders in the pain wash
        // ink per SPScreensV2.jsx L369), so `applyTone` re-renders the text —
        // that is also what makes the value follow a light/dark flip, since
        // `refreshDynamicColors` goes through the same call.
        applyTone(Self.tone(for: balance))
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

    /// Visual tone of the balance pill (#232). `zero` (pain chrome +
    /// IconCoinOff) outranks `low` (warn chrome) — both can't show at
    /// once and an empty wallet is the more urgent story. The alarms in
    /// the list stay visually active in every tone: at 0 ₽ they still
    /// fire, the user just can't pay to snooze them.
    private enum PillTone {
        case normal
        case low
        case zero
    }

    private static func tone(for balance: Decimal) -> PillTone {
        let value = NSDecimalNumber(decimal: balance).doubleValue
        if value <= 0 { return .zero }
        if value <= lowBalanceThreshold { return .low }
        return .normal
    }

    // MARK: - Subviews

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        // h1 32pt extrabold with -0.02em kerning per `tokens.css` L80.
        label.font = AppTypography.h1
        label.textColor = AppColors.fg1
        label.attributedText = NSAttributedString(
            string: Localized.text("alarms.title"),
            attributes: [
                .font: AppTypography.h1,
                // Full `letterSpacing: -.02em` per SPScreensV2.jsx L315 — the
                // earlier value was halved (#280). `kern(em:size:)` resolves the
                // em tracking to points for the 32pt h1.
                .kern: AppTypography.kern(em: -0.02, size: 32),
                .foregroundColor: AppColors.fg1
            ]
        )
        return label
    }()

    /// 40×40 whiteOverlay06 circle hosting the gear glyph — the in-header
    /// Settings entry point (SPScreensV2.jsx L318-324). Sits left of the
    /// money "+"; tapping it routes through `onSettingsTap`.
    private let settingsButton: UIControl = {
        let view = UIControl()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 20
        view.layer.masksToBounds = true
        view.backgroundColor = AppColors.whiteOverlay06
        return view
    }()

    private let settingsIconView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFit
        view.tintColor = AppColors.fg2
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        view.image = UIImage(systemName: "gearshape", withConfiguration: config)
        view.isUserInteractionEnabled = false
        return view
    }()

    private let addButton: UIControl = {
        let view = UIControl()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 20
        view.layer.masksToBounds = false
        // Money-tinted drop shadow — matches `--sp-shadow-money`. The colour
        // is resolved per trait in `refreshDynamicColors`: a `static let`
        // initializer runs with whatever `UITraitCollection.current` happens
        // to be, which is not this view's theme.
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

    /// Pill corner radius — 14px in SPScreensV2.jsx, between `AppRadius.sm`
    /// and `.md`. Named so the shadow path, the wash layer and the view itself
    /// cannot drift apart.
    private static let pillCornerRadius: CGFloat = 14

    private let pillButton: UIControl = {
        let view = UIControl()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = SPAlarmsListHeader.pillCornerRadius
        // NOT clipped: a `masksToBounds` layer cannot render a drop shadow,
        // and light mode needs one to separate the pill from the page. The
        // only subview that reached the pill's edges is the zero-balance
        // wash, which now rounds itself.
        view.layer.masksToBounds = false
        view.layer.borderWidth = 1
        return view
    }()

    /// Reddish wash behind the pill content in the zero-balance state —
    /// `linear-gradient(135deg, pain@.10 → pain@.02)` per SPScreensV2.jsx
    /// L346-347. Hidden in the neutral / warn tones, where the flat
    /// `backgroundColor` carries the surface instead.
    private let zeroTintGradient: SPGradientView = {
        // Stops are (re)applied per trait in `applyTone` — see `zeroWashColors`.
        let view = SPGradientView(colors: [], locations: [0.0, 1.0])
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isUserInteractionEnabled = false
        view.isHidden = true
        // The wash fills the pill edge to edge, so it carries the corner
        // rounding the pill itself gave up in order to cast a shadow.
        view.layer.cornerRadius = SPAlarmsListHeader.pillCornerRadius
        view.layer.masksToBounds = true
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
        // Code-drawn wallet glyph (SPScreensV2.jsx L359) — replaces the
        // SF `creditcard.fill` so the pill matches the V3 icon set (#280).
        view.image = SPIcons.wallet(size: 18)
        return view
    }()

    private let balanceCapsLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.attributedText = NSAttributedString(
            string: Localized.text("common.caps.balance"),
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: AppColors.fg3
            ]
        )
        return label
    }()

    /// 14pt mono bold balance amount. The design uses `700 14px/18px mono`
    /// with `letter-spacing: 0` (SPScreensV2.jsx L364-369) — a compact inline
    /// value, NOT the 20pt `moneyMd` hero number the pill carried before
    /// (#280). Built in `pillValueFont` so `setBalance` and this declaration
    /// agree on one source.
    private static let pillValueFont = AppFonts.mono(.bold, 14)

    private let balanceValueLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        // 14pt mono bold — compact inline amount. Tabular nums via the mono
        // font; tracking stays at 0 per the design.
        label.font = SPAlarmsListHeader.pillValueFont
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
        title: Localized.text("common.button.top_up"),
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

    /// `applyTone` renders the amount, and it runs once during `configure`
    /// too — before the controller has pushed anything. Without this the pill
    /// would flash "0 ₽" on construction.
    private var hasBalance = false

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
        refreshChrome()
        applyTone(Self.tone(for: currentBalance))
    }

    /// Re-resolve everything that lives on a `CALayer` outside the pill.
    /// `cgColor` and `CAGradientLayer.colors` are snapshots — they keep the
    /// theme that was current when they were assigned, which for a `static
    /// let` property initializer is not this view's theme at all.
    private func refreshChrome() {
        let trait = traitCollection
        bottomHairline.backgroundColor = AppColors.whiteOverlay06
        addButton.layer.shadowColor = AppColors.money500.resolvedColor(with: trait).cgColor
        addButtonGradient.refresh(
            colors: SPSupport.moneyGradientColors(for: trait),
            locations: SPSupport.moneyGradientLocations
        )
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Pre-rasterise the pill shadow against its rounded path and keep the
        // light-mode ambient stop's frame in sync with the pill bounds.
        pillButton.layer.shadowPath = UIBezierPath(
            roundedRect: pillButton.bounds,
            cornerRadius: Self.pillCornerRadius
        ).cgPath
        AppShadow.installAmbientShadow1Layer(
            on: pillButton.layer,
            cornerRadius: Self.pillCornerRadius,
            trait: traitCollection
        )
    }

    // MARK: - Configuration

    // swiftlint:disable:next function_body_length
    private func configure() {
        backgroundColor = AppColors.bg0

        addSubview(titleLabel)
        addSubview(settingsButton)
        settingsButton.addSubview(settingsIconView)
        addSubview(addButton)
        addButton.addSubview(addButtonGradient)
        addButton.addSubview(addIconView)

        addSubview(pillButton)
        pillButton.addSubview(zeroTintGradient)
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
        settingsButton.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)
        pillButton.addTarget(self, action: #selector(pillTapped), for: .touchUpInside)
        topUpButton.addTarget(self, action: #selector(topUpTapped), for: .touchUpInside)

        let inset = AppSpacing.screenInset

        // The hint's bottom EQUALITY is what gives the pill — and therefore
        // the whole header — a defined height. With only a `≤` here the
        // header height is ambiguous and the solver is free to stretch the
        // pill to fill the screen (it did). Priority 999 so transient
        // zero-frame layout passes don't hard-conflict.
        let hintBottom = balanceHintLabel.bottomAnchor.constraint(
            equalTo: pillButton.bottomAnchor,
            constant: -AppSpacing.sp3
        )
        hintBottom.priority = UILayoutPriority(999)

        NSLayoutConstraint.activate([
            // ── Title row ─────────────────────────────────────────────
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: AppSpacing.sp2),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            titleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: settingsButton.leadingAnchor,
                constant: -AppSpacing.sp3
            ),

            // Gear — 40×40 circle left of the money "+", 10pt gap between the
            // two (SPScreensV2.jsx L316).
            settingsButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            settingsButton.trailingAnchor.constraint(equalTo: addButton.leadingAnchor, constant: -10),
            settingsButton.widthAnchor.constraint(equalToConstant: 40),
            settingsButton.heightAnchor.constraint(equalToConstant: 40),

            settingsIconView.centerXAnchor.constraint(equalTo: settingsButton.centerXAnchor),
            settingsIconView.centerYAnchor.constraint(equalTo: settingsButton.centerYAnchor),

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

            // Zero-balance pain wash fills the pill behind the content.
            zeroTintGradient.topAnchor.constraint(equalTo: pillButton.topAnchor),
            zeroTintGradient.leadingAnchor.constraint(equalTo: pillButton.leadingAnchor),
            zeroTintGradient.trailingAnchor.constraint(equalTo: pillButton.trailingAnchor),
            zeroTintGradient.bottomAnchor.constraint(equalTo: pillButton.bottomAnchor),

            // Wallet icon — 40×40 leading. The top inequality keeps the
            // pill at least 64pt tall so the tile can never overflow when
            // the text column measures shorter than the tile.
            walletIconHost.leadingAnchor.constraint(equalTo: pillButton.leadingAnchor, constant: AppSpacing.sp3),
            walletIconHost.centerYAnchor.constraint(equalTo: pillButton.centerYAnchor),
            walletIconHost.topAnchor.constraint(greaterThanOrEqualTo: pillButton.topAnchor, constant: AppSpacing.sp3),
            walletIconHost.widthAnchor.constraint(equalToConstant: 40),
            walletIconHost.heightAnchor.constraint(equalToConstant: 40),

            walletIconImageView.centerXAnchor.constraint(equalTo: walletIconHost.centerXAnchor),
            walletIconImageView.centerYAnchor.constraint(equalTo: walletIconHost.centerYAnchor),

            // Top-up button — sm, trailing.
            topUpButton.trailingAnchor.constraint(equalTo: pillButton.trailingAnchor, constant: -AppSpacing.sp3),
            topUpButton.centerYAnchor.constraint(equalTo: pillButton.centerYAnchor),

            // Balance value row — baseline-aligned caps «БАЛАНС» + amount.
            balanceCapsLabel.leadingAnchor.constraint(
                equalTo: walletIconHost.trailingAnchor,
                constant: AppSpacing.sp3
            ),
            balanceCapsLabel.topAnchor.constraint(equalTo: pillButton.topAnchor, constant: AppSpacing.sp3),

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
            balanceHintLabel.topAnchor.constraint(
                equalTo: balanceValueLabel.bottomAnchor,
                constant: AppSpacing.sp1 / 2
            ),
            balanceHintLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: topUpButton.leadingAnchor,
                constant: -AppSpacing.sp3
            ),
            hintBottom,

            // ── Bottom hairline ───────────────────────────────────────
            bottomHairline.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomHairline.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomHairline.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomHairline.heightAnchor.constraint(equalToConstant: 1)
        ])

        refreshChrome()
        applyTone(.normal)
    }

    /// Switch the pill chrome between the neutral (bg2 + whiteOverlay08
    /// stroke), warn (warn500@12% + warn500@45% stroke) and zero-balance
    /// pain (pain gradient wash + pain500@30% stroke + IconCoinOff tile,
    /// #232) variants. The hint colour also shifts so the state stays
    /// legible at a glance without an extra banner row. The «Пополнить»
    /// CTA keeps its money variant in every tone — topping up is a
    /// positive action even when the wallet is empty.
    private func applyTone(_ tone: PillTone) {
        let trait = traitCollection
        zeroTintGradient.isHidden = tone != .zero
        zeroTintGradient.refresh(colors: Self.zeroWashColors(for: trait), locations: [0.0, 1.0])
        switch tone {
        case .zero:
            // The pain wash gradient carries the surface; flat bg clears.
            pillButton.backgroundColor = .clear
            pillButton.layer.borderColor = AppColors.pain500
                .resolvedColor(with: trait)
                .withAlphaComponent(0.30).cgColor
            // NOT `pain300`: on the light wash that is 2.77:1. `fgOnPainWash`
            // keeps the dark theme's glow (pain300, 10.82:1) and swaps in
            // `pain600` for light (7.41:1).
            balanceHintLabel.textColor = AppColors.fgOnPainWash
            walletIconHost.refresh(
                colors: SPSupport.painGradientColors(for: trait),
                locations: SPSupport.painGradientLocations
            )
            // Crossed-out coin on the pain tile — `fgOnPain` is the token for
            // ink on a solid pain fill, and is white in both themes.
            walletIconImageView.image = SPIcons.coinOff(size: 18)
            walletIconImageView.tintColor = AppColors.fgOnPain
        case .low:
            // Fill takes the canon amber (#520); the border deliberately does
            // NOT. A stroke has to be seen against the page, and at 45% the
            // ink tone measures 2.07:1 there where amber measures 1.38:1.
            pillButton.backgroundColor = AppColors.warnFill500.withAlphaComponent(0.12)
            pillButton.layer.borderColor = AppColors.warn500
                .resolvedColor(with: trait)
                .withAlphaComponent(0.45).cgColor
            // Same trap as above: `warn300` is 2.83:1 on the light wash.
            // `fgOnWarnWash` is the ink half of the wash pair (7.85:1).
            balanceHintLabel.textColor = AppColors.fgOnWarnWash
            restoreWalletTile()
        case .normal:
            pillButton.backgroundColor = AppColors.bg2
            pillButton.layer.borderColor = AppColors.whiteOverlay08
                .resolvedColor(with: trait).cgColor
            balanceHintLabel.textColor = AppColors.fg3
            restoreWalletTile()
        }
        if hasBalance {
            balanceValueLabel.attributedText = MoneyFormatter.attributed(
                currentBalance,
                digitsFont: Self.pillValueFont,
                // The 0 ₽ amount sits on the same wash as the hint, so it
                // takes the same ink; other tones keep the label's `fg1`.
                color: tone == .zero ? AppColors.fgOnPainWash : nil
            )
        }
        applyPillElevation(trait)
    }

    /// `linear-gradient(135deg, pain@.10 → pain@.02)` resolved for `trait` —
    /// the zero-balance wash. Handed over as `CGColor`s, so it has to be
    /// re-applied on a theme flip rather than resolved once at `init`.
    private static func zeroWashColors(for trait: UITraitCollection) -> [CGColor] {
        let base = AppColors.pain500.resolvedColor(with: trait)
        return [base.withAlphaComponent(0.10).cgColor, base.withAlphaComponent(0.02).cgColor]
    }

    /// Lift the pill off the page. In light the pill is a near-white surface
    /// on a near-white page (`bg2` on `bg0` is 1.07:1) — it needs the shadow
    /// *and* the stroke it already carries; dark keeps the flat outlined pill,
    /// where `bg2` on `bg0` is already a visible step.
    private func applyPillElevation(_ trait: UITraitCollection) {
        if trait.userInterfaceStyle == .dark {
            pillButton.layer.shadowOpacity = 0
        } else {
            AppShadow.shadow1(for: trait).apply(to: pillButton.layer)
        }
        AppShadow.installAmbientShadow1Layer(
            on: pillButton.layer,
            cornerRadius: Self.pillCornerRadius,
            trait: trait
        )
    }

    /// Reset the 40×40 leading tile back to its money-gradient wallet
    /// recipe after a visit to the zero-balance pain variant.
    private func restoreWalletTile() {
        walletIconHost.refresh(
            colors: SPSupport.moneyGradientColors(for: traitCollection),
            locations: SPSupport.moneyGradientLocations
        )
        walletIconImageView.image = SPIcons.wallet(size: 18)
        walletIconImageView.tintColor = AppColors.fgOnMoney
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

    @objc private func settingsTapped() {
        SPSupport.animatePress(settingsButton, pressed: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + SPSupport.durationQuick) { [weak self] in
            guard let self else { return }
            SPSupport.animatePress(self.settingsButton, pressed: false)
        }
        onSettingsTap?()
    }

    @objc private func pillTapped() {
        // Tapping the body of the pill (anywhere except the explicit
        // «Пополнить» CTA) is a shortcut to the same destination — keeps
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
