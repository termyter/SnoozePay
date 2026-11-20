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
/// the urgency is now folded directly into the pill: when the host reports a
/// low balance (`AlarmsListViewModel.isLowBalance`) the pill switches its background
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
    /// this tab. Handoff only — the canon header has the "+" alone:
    /// `docs/design/v2-handoff/components/SPScreensV2.jsx:316-333` contains "Settings — opens screen 23".
    var onSettingsTap: (() -> Void)?

    /// Kept for binary-compatibility with the legacy header — the V2
    /// pill folds the warning state into itself, so this callback now
    /// routes through the same «Пополнить» tap path.
    var onWarnTopUpTap: (() -> Void)?

    /// Update the balance pill in place. The pill switches between three
    /// tones: pain when the balance is 0 (zero-balance state, #232), warn-tint
    /// when `isLow`, neutral otherwise. `isLow` is the host's
    /// `AlarmsListViewModel.isLowBalance`, whose threshold follows the price
    /// context (#1151) — the pill no longer keeps its own «≤ 100 of any
    /// currency», which tinted a $5.00 wallet as low.
    /// `hint` and `delta` are accepted for source-compat with the legacy
    /// header; `delta` is currently ignored in the V2 pill layout (the
    /// rolling-week change rendered as `↑/↓ amount` migrates onto the
    /// Wallet screen). Pass through unchanged so existing call sites
    /// keep compiling.
    func setBalance(_ balance: Decimal, currency: Currency, hint: String?, isLow: Bool, delta: Decimal? = nil) {
        _ = delta // accepted for API compat; pill omits the delta row.
        currentBalance = balance
        currentCurrency = currency
        currentIsLow = isLow
        hasBalance = true
        // The amount's ink is part of the tone (0 ₽ renders in the pain wash
        // ink; the zero-balance pill is handoff only,
        // `docs/design/v2-handoff/components/SPScreensV2.jsx:366-369` contains "fmtRub(840)}"),
        // so `applyTone` re-renders the text — that is also what makes the
        // value follow a light/dark flip, since `refreshDynamicColors` goes
        // through the same call.
        applyTone(Self.tone(for: balance, isLow: isLow))
        if let hint = hint, !hint.isEmpty {
            balanceHintLabel.text = hint
            balanceHintLabel.isHidden = false
        } else {
            balanceHintLabel.isHidden = true
        }
    }

    // MARK: - Tokens

    /// Visual tone of the balance pill (#232). `zero` (pain chrome +
    /// IconCoinOff) outranks `low` (warn chrome) — both can't show at
    /// once and an empty wallet is the more urgent story. The alarms in
    /// the list stay visually active in every tone: at 0 ₽ they still
    /// fire, the user just can't pay to snooze them.
    enum PillTone {
        case normal
        case low
        case zero
    }

    /// The tone last applied — read by tests.
    private(set) var pillTone: PillTone = .normal

    private static func tone(for balance: Decimal, isLow: Bool) -> PillTone {
        if NSDecimalNumber(decimal: balance).doubleValue <= 0 { return .zero }
        return isLow ? .low : .normal
    }

    // MARK: - Subviews

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        // h1 32pt extrabold with -0.02em kerning per `tokens.css` L80.
        // Text is set in `renderText`. One word, so it cannot wrap: at the
        // largest sizes it shrinks to fit beside the buttons, never "…".
        label.font = AppTypography.h1
        label.textColor = AppColors.fg1
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        return label
    }()

    /// 40×40 whiteOverlay06 circle hosting the gear glyph — the in-header
    /// Settings entry point, handoff only,
    /// `docs/design/v2-handoff/components/SPScreensV2.jsx:318-324` contains "IconSettings size={18}".
    /// Sits left of the money "+"; tapping it routes through `onSettingsTap`.
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
    /// `linear-gradient(135deg, pain@.10 → pain@.02)`, handoff only,
    /// `docs/design/v2-handoff/components/SPScreensV2.jsx:347` contains "rgba(244,82,63,.10) 0%, rgba(244,82,63,.02)".
    /// Hidden in the neutral / warn tones, where the flat `backgroundColor`
    /// carries the surface instead.
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
        // Code-drawn wallet glyph,
        // `docs/design/snoozepay-2026-04-27/project/components/SPScreensV2.jsx:320` contains "IconWallet size={18}",
        // replaces the SF `creditcard.fill` so the pill matches the V3 icon
        // set (#280).
        view.image = SPIcons.wallet(size: 18)
        return view
    }()

    private let balanceCapsLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        // One word: it never wraps. Above the amount's 750 so, when the row is
        // tight, the shrink-to-fit amount gives way and «БАЛАНС» stays whole.
        label.numberOfLines = 1
        label.setContentCompressionResistancePriority(UILayoutPriority(751), for: .horizontal)
        return label
    }()

    /// 14pt mono bold balance amount. The handoff uses `700 14px/18px mono`
    /// with `letter-spacing: 0` — a compact inline value, NOT the 20pt
    /// `moneyMd` hero number the pill carried before (#280):
    /// `docs/design/v2-handoff/components/SPScreensV2.jsx:364-369` contains "700 14px/18px".
    /// The canon pill still uses `--sp-t-money-md`,
    /// `docs/design/snoozepay-2026-04-27/project/components/SPScreensV2.jsx:325` contains "840 ₽</span>".
    /// Built in `pillValueFont` so `setBalance` and this declaration agree on
    /// one source.
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
        // When the 64pt tile floor leaves the pill taller than its text, the
        // amount and the hint would share the slack arbitrarily: the solver's
        // pick depended on constraint activation order and moved the amount
        // 1.7pt down on a cold start (#1111). The amount hugs; the hint takes it.
        label.setContentHuggingPriority(.defaultHigh, for: .vertical)
        return label
    }()

    private let balanceHintLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = AppTypography.scaledMeta
        label.adjustsFontForContentSizeCategory = true
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
    private var currentCurrency: Currency?
    private var currentIsLow = false

    /// `applyTone` renders the amount, and it runs once during `configure`
    /// too — before the controller has pushed anything. Without this the pill
    /// would flash "0 ₽" on construction.
    private var hasBalance = false

    /// Default sizes: the amount after «БАЛАНС» on one baseline, the button
    /// centred, the one-line hint in the column left of the button.
    /// From XL up (`AppTypography.stacksDenseRows`) that row no longer fits a
    /// 375pt phone: the amount drops under «БАЛАНС», the button moves to the
    /// top, and the hint wraps across the full width below it (#1111).
    private var rowLayout: [NSLayoutConstraint] = []
    private var stackedLayout: [NSLayoutConstraint] = []

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: SPAlarmsListHeader, _) in
                view.refreshDynamicColors()
            }
        }
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: SPAlarmsListHeader, _) in
            view.renderText()
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
        applyTone(Self.tone(for: currentBalance, isLow: currentIsLow))
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
            // two (handoff only),
            // `docs/design/v2-handoff/components/SPScreensV2.jsx:316-317` contains "Settings — opens screen 23".
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

            // Top-up button — sm, trailing; vertical placement per arrangement.
            topUpButton.trailingAnchor.constraint(equalTo: pillButton.trailingAnchor, constant: -AppSpacing.sp3),

            // Balance value row — baseline-aligned caps «БАЛАНС» + amount.
            balanceCapsLabel.leadingAnchor.constraint(
                equalTo: walletIconHost.trailingAnchor,
                constant: AppSpacing.sp3
            ),
            balanceCapsLabel.topAnchor.constraint(equalTo: pillButton.topAnchor, constant: AppSpacing.sp3),

            balanceCapsLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: topUpButton.leadingAnchor,
                constant: -AppSpacing.sp3
            ),

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
                greaterThanOrEqualTo: balanceValueLabel.bottomAnchor,
                constant: AppSpacing.sp1 / 2
            ),
            hintBottom,

            // ── Bottom hairline ───────────────────────────────────────
            bottomHairline.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomHairline.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomHairline.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomHairline.heightAnchor.constraint(equalToConstant: 1)
        ])

        rowLayout = [
            balanceValueLabel.leadingAnchor.constraint(
                equalTo: balanceCapsLabel.trailingAnchor,
                constant: AppSpacing.sp2
            ),
            balanceValueLabel.firstBaselineAnchor.constraint(equalTo: balanceCapsLabel.firstBaselineAnchor),
            topUpButton.centerYAnchor.constraint(equalTo: pillButton.centerYAnchor),
            balanceHintLabel.topAnchor.constraint(
                equalTo: balanceValueLabel.bottomAnchor,
                constant: AppSpacing.sp1 / 2
            ),
            balanceHintLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: topUpButton.leadingAnchor,
                constant: -AppSpacing.sp3
            )
        ]
        // The hint sits right under the amount when the button allows it
        // (750), and never above the button's bottom edge.
        let hintUnderAmount = balanceHintLabel.topAnchor.constraint(
            equalTo: balanceValueLabel.bottomAnchor,
            constant: AppSpacing.sp1 / 2
        )
        hintUnderAmount.priority = .defaultHigh
        stackedLayout = [
            balanceValueLabel.leadingAnchor.constraint(equalTo: balanceCapsLabel.leadingAnchor),
            balanceValueLabel.topAnchor.constraint(
                equalTo: balanceCapsLabel.bottomAnchor,
                constant: AppSpacing.sp1 / 2
            ),
            topUpButton.topAnchor.constraint(equalTo: pillButton.topAnchor, constant: AppSpacing.sp3),
            hintUnderAmount,
            balanceHintLabel.topAnchor.constraint(
                greaterThanOrEqualTo: topUpButton.bottomAnchor,
                constant: AppSpacing.sp2
            ),
            balanceHintLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: pillButton.trailingAnchor,
                constant: -AppSpacing.sp3
            )
        ]

        refreshChrome()
        renderText()
    }

    /// Re-render the hand-built attributed labels at the current content size
    /// category and pick the balance row's arrangement. Every role is its
    /// fixed font at the default category, so the header is unchanged there.
    private func renderText() {
        let traits = traitCollection
        let titleFont = AppTypography.scaledH1(compatibleWith: traits)
        titleLabel.attributedText = NSAttributedString(
            string: Localized.text("alarms.title"),
            attributes: [
                .font: titleFont,
                // Full `letterSpacing: -.02em` per
                // `docs/design/snoozepay-2026-04-27/project/components/SPScreensV2.jsx:296` contains "Будильники</div>"
                // — the earlier value was halved (#280). `kern(em:size:)`
                // resolves the em tracking to points for the h1 size.
                .kern: AppTypography.kern(em: -0.02, size: titleFont.pointSize),
                .foregroundColor: AppColors.fg1
            ]
        )
        let capsFont = AppTypography.scaledCaps(compatibleWith: traits)
        balanceCapsLabel.attributedText = NSAttributedString(
            string: Localized.text("common.caps.balance"),
            attributes: [
                .font: capsFont,
                .kern: AppTypography.kerning(
                    AppTypography.capsKerning, of: AppTypography.caps, scaledTo: capsFont
                ),
                .foregroundColor: AppColors.fg3
            ]
        )
        let stacked = AppTypography.stacksDenseRows(traits.preferredContentSizeCategory)
        NSLayoutConstraint.deactivate(stacked ? rowLayout : stackedLayout)
        NSLayoutConstraint.activate(stacked ? stackedLayout : rowLayout)
        // One line shrinking to 0.8 in the row, as before; wrapping when stacked.
        balanceHintLabel.numberOfLines = stacked ? 0 : 1
        balanceHintLabel.adjustsFontSizeToFitWidth = !stacked
        // Before the first `setBalance` there is no amount to tone by.
        applyTone(hasBalance ? Self.tone(for: currentBalance, isLow: currentIsLow) : pillTone)
    }

    /// The 14pt amount, scaled as `.subheadline` (15pt) and capped at 2×.
    private var scaledPillValueFont: UIFont {
        AppTypography.scaled(Self.pillValueFont, as: .subheadline, compatibleWith: traitCollection)
    }

    /// Switch the pill chrome between the neutral (bg2 + whiteOverlay08
    /// stroke), warn (warn500@12% + warn500@45% stroke) and zero-balance
    /// pain (pain gradient wash + pain500@30% stroke + IconCoinOff tile,
    /// #232) variants. The hint colour also shifts so the state stays
    /// legible at a glance without an extra banner row. The «Пополнить»
    /// CTA keeps its money variant in every tone — topping up is a
    /// positive action even when the wallet is empty.
    private func applyTone(_ tone: PillTone) {
        pillTone = tone
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
        if hasBalance, let currentCurrency {
            balanceValueLabel.attributedText = MoneyFormatter.attributed(
                currentBalance,
                currency: currentCurrency,
                digitsFont: scaledPillValueFont,
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
