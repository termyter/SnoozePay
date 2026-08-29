import StoreKit
import UIKit
import os

/// Bottom-sheet presented over `AlarmFiringViewController` when the user wants
/// to top up the wallet mid-alarm so they can keep snoozing.
///
/// V2 spec: `docs/design/v2-handoff/components/SPTopUp.jsx`
/// `FiringTopUpPresets` (lines 103–197). Three vertical preset rows feed a
/// single Apple Pay primary CTA; each row's amount is the catalogue amount of
/// its mapped SKU (#275/#297) so display == charge == credit. Visuals match the
/// V2 design system — bg1 surface, 28pt top corners, a pulsing warn dot + caps
/// «Будильник на паузе · MM:SS» + h2 «Пополнить баланс» header, full-width
/// preset rows, money-toned Apple Pay button, footer meta.
///
/// Side effects beyond pixel layout:
/// - On `viewWillAppear` the alarm audio + escalation timer are paused via
///   `AudioService.pauseAlarmSound()`. A 60-second auto-resume timer starts
///   so an abandoned sheet can't keep the alarm silent indefinitely.
/// - On a successful purchase the controller flips to a green-checkmark
///   "+N ₽" success state and auto-dismisses after 2 seconds.
/// - On dismissal (any path: cancel, success-auto, 60s-timeout) the audio
///   resumes unless the alarm was already stopped externally.
final class FiringTopUpBottomSheetViewController: UIViewController {

    // MARK: - Preset model

    /// One of the three top-up tiles. The displayed `amount` is NOT a free
    /// literal — it is derived from the mapped SKU's catalogue amount (or, once
    /// loaded, the resolved StoreKit product price) so display == charge ==
    /// credit. See #275: the tiles used to render rounded literals (200 / 500 /
    /// 1000 ₽) over the 149 / 499 / 999 SKUs, charging and crediting less than
    /// shown. The lineup (which SKUs exist) is PM's #240 — this only guarantees
    /// the rendered number is honest for the current catalogue.
    struct Preset {
        /// RUB amount to display AND credit. Always equals the catalogue amount
        /// of `productID` for the current catalogue (or the real product price
        /// once `StoreKitService` has loaded it).
        let amount: Int
        let popular: Bool
        /// StoreKit product ID. Falls back to `BalanceService.topUp(amount:)`
        /// when not loaded so debug paths still credit the wallet — with the
        /// SAME `amount` shown, never a rounded literal.
        let productID: String

        /// Build a preset whose displayed amount is the catalogue amount of the
        /// supplied SKU. Returns nil for an unknown SKU so we never render an
        /// invented number.
        init?(productID: String, popular: Bool) {
            guard let catalogAmount = StoreKitService.catalogAmount(for: productID) else { return nil }
            self.amount = catalogAmount
            self.popular = popular
            self.productID = productID
        }
    }

    /// Default preset list. Amounts are resolved from the SKU catalogue so each
    /// row shows exactly what the App Store charges and the ledger credits
    /// (#297).
    ///
    /// Row titles and hints used to live here as literals from the design comp
    /// («+1 откладывание · ровно на сейчас» over the 149 ₽ SKU). They are gone:
    /// the copy is a function of the CURRENT snooze price, so it is computed at
    /// render time by `FiringTopUpCopy` (#548).
    static let defaultPresets: [Preset] = [
        Preset(productID: "io.mobilife.snoozepay.balance.149", popular: false),
        Preset(productID: "io.mobilife.snoozepay.balance.499", popular: true),
        Preset(productID: "io.mobilife.snoozepay.balance.999", popular: false)
    ].compactMap { $0 }

    // MARK: - Configuration

    private let presets: [Preset]

    /// Price of the NEXT snooze — `AlarmFiringViewModel.currentPenalty`, so the
    /// progressive rung the user is about to pay, not the alarm's base price.
    /// Every label on the sheet is derived from it (#548); `0` means the caller
    /// had no price to give (free alarm / preview route) and the copy degrades
    /// to price-free wording rather than assuming a default.
    private let snoozePrice: Double

    /// Wallet balance the purchase lands on top of. Part of the arithmetic:
    /// with 100 ₽ already banked a 149 ₽ top-up DOES unlock a 200 ₽ snooze.
    private let currentBalance: Double

    /// Auto-resume timeout. Spec is 60 seconds. Stored as a constant so the
    /// controller doesn't re-read a magic literal across timer setup, label
    /// seed, and countdown formatting.
    private let autoResumeTimeout: TimeInterval = 60

    /// Fired when the sheet is dismissed for any reason. Owner uses this to
    /// resume the escalation timer / refresh snooze affordance.
    var onDismiss: (() -> Void)?

    // MARK: - State

    private var selectedAmount: Int

    /// Set to true once we've kicked off Apple Pay so the auto-resume timer
    /// doesn't yank the sheet out from under the StoreKit dialog.
    private var purchaseInFlight: Bool = false

    /// Flips when StoreKit reports a successful credit. Drives the success
    /// state UI swap + the 2-second auto-dismiss timer.
    private var successAmount: Int?

    /// Auto-resume timeout timer (60s). Reset to nil whenever the sheet is
    /// about to dismiss so a queued tick can't fire after teardown.
    private var autoResumeTimer: Timer?

    /// Visible mm:ss countdown reflected in the pause label. Decremented every
    /// 1s so the user can see how long they have left to commit.
    private var remainingSeconds: Int

    /// 1Hz countdown timer feeding `pauseLabel`.
    private var countdownTimer: Timer?

    /// Notification observer tokens torn down in `deinit`.
    private var purchaseCompletedObserver: NSObjectProtocol?
    private var purchaseFailedObserver: NSObjectProtocol?
    /// True while registered as a purchase-feedback subscriber so begin/end
    /// stay balanced across appear/disappear (#45).
    private var isObservingPurchaseFeedback = false

    // MARK: - Subviews

    private let dragHandle: UIView = {
        let view = UIView()
        view.backgroundColor = AppColors.whiteOverlay12
        view.layer.cornerRadius = 2
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    /// h2 «Пополнить баланс» header (`SPTopUp.jsx:138`).
    private let titleH2Label: UILabel = {
        let label = UILabel()
        label.font = AppTypography.h2
        label.textColor = .white
        label.text = "Пополнить баланс"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    /// Pulsing 8pt warn dot to the left of the pause caps (`SPTopUp.jsx:136`).
    private let pauseDot: UIView = {
        let view = UIView()
        view.backgroundColor = AppColors.warn400
        view.layer.cornerRadius = 4
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    /// Caps pause countdown «Будильник на паузе · 00:54» (`SPTopUp.jsx:137`).
    private let pauseLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        return label
    }()

    private let closeButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "xmark")
        config.baseForegroundColor = AppColors.fg3
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = AppTypography.body
        label.textColor = AppColors.fg2
        label.numberOfLines = 0
        // Text seeded in `setupUI` from `FiringTopUpCopy.subtitle` so the copy
        // follows the current snooze price instead of naming the cheapest SKU
        // and calling it the amount a snooze needs — #275/#548.
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    /// Vertical column of full-width preset rows (`SPTopUp.jsx:144-175`): each
    /// row shows the «+1 откладывание» title + hint on the left and the rouble
    /// amount + a check chip on the right when selected.
    private var presetRows: [FiringTopUpPresetRow] = []
    private let presetStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = AppSpacing.sp2
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    /// Apple Pay primary CTA. Money tone with applelogo icon + suffix that
    /// tracks the selected preset. Rebuilt on every selection because
    /// SPButton title/suffix is immutable post-init.
    private lazy var applePayButton: SPButton = makeApplePayButton(amount: selectedAmount)

    /// Footer meta line — "Зачислится мгновенно. Откладывание будет доступно
    /// сразу." Replaces the V1 cancel button (the close X in the header
    /// covers the same affordance).
    private let footerMetaLabel: UILabel = {
        let label = UILabel()
        label.font = AppTypography.meta
        label.textColor = AppColors.fg3
        label.textAlignment = .center
        label.numberOfLines = 0
        label.text = "Зачислится мгновенно. Откладывание будет доступно сразу."
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    /// Full-screen overlay shown after a successful purchase.
    private let successContainer: UIView = {
        let view = UIView()
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let successCheck: UIImageView = {
        let configuration = UIImage.SymbolConfiguration(pointSize: 48, weight: .bold)
        let image = UIImage(systemName: "checkmark", withConfiguration: configuration)
        let view = UIImageView(image: image)
        view.tintColor = AppColors.fgOnMoney
        view.contentMode = .center
        view.backgroundColor = AppColors.money500
        view.layer.cornerRadius = 48
        view.layer.masksToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let successAmountLabel: UILabel = {
        let label = UILabel()
        label.font = AppTypography.moneyXl
        label.textColor = AppColors.money400
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let successCaption: UILabel = {
        let label = UILabel()
        label.font = AppTypography.body
        label.textColor = AppColors.fg2
        label.textAlignment = .center
        label.text = "Возвращаем к будильнику через 2 секунды"
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - Init

    init(
        presets: [Preset] = defaultPresets,
        snoozePrice: Double = 0,
        currentBalance: Double = BalanceService.shared.balance
    ) {
        self.presets = presets
        self.snoozePrice = snoozePrice
        self.currentBalance = currentBalance
        // Pre-select the cheapest tier that actually unlocks a snooze at the
        // current price (#548). The comp pre-selected the SMALLEST tier
        // (`SPTopUp.jsx:118`) — correct only while the cheapest SKU covered the
        // price; at 200 ₽ it opened on a 149 ₽ tier that buys nothing. Falls
        // back to 0 (no invented literal) if the list is empty — #275/#297.
        self.selectedAmount = FiringTopUpCopy.recommendedAmount(
            from: presets.map(\.amount),
            balance: currentBalance,
            price: snoozePrice
        ) ?? 0
        self.remainingSeconds = 60
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        if let sheet = sheetPresentationController {
            // Custom ~440pt detent matches the design comp height (header +
            // preset row + apple pay + footer). Falls back to .medium on
            // older runtimes.
            if #available(iOS 16.0, *) {
                // ~560pt — header + three full-width preset rows + apple pay +
                // footer. Taller than the old horizontal-tile comp (#288).
                let custom = UISheetPresentationController.Detent.custom(
                    identifier: UISheetPresentationController.Detent.Identifier("snoozepay.topup")
                ) { _ in 560 }
                sheet.detents = [custom, .large()]
            } else {
                sheet.detents = [.medium(), .large()]
            }
            sheet.prefersGrabberVisible = false  // we render our own drag handle
            sheet.preferredCornerRadius = AppRadius.xl
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let token = purchaseCompletedObserver {
            NotificationCenter.default.removeObserver(token)
        }
        if let token = purchaseFailedObserver {
            NotificationCenter.default.removeObserver(token)
        }
        autoResumeTimer?.invalidate()
        countdownTimer?.invalidate()
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        // Sheet surface bg1 per `SPTopUp.jsx:135-142` (#288).
        view.backgroundColor = AppColors.bg1
        // Per the spec the firing screen overlay is dark; pin the sheet to
        // dark so SPAmountPreset / SPButton tokens resolve against the same
        // palette as the host VC.
        overrideUserInterfaceStyle = .dark
        setupUI()
        setupPresetTiles()
        observePurchaseNotifications()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Pause audio + escalation immediately so the user isn't fighting
        // the alarm sound while choosing a preset.
        AudioService.shared.pauseAlarmSound()
        AlarmFiringCoordinator.shared.pauseEscalation()
        startAutoResumeTimer()
        startCountdownTimer()
        updatePauseLabel()
        // While visible, route purchase feedback to the in-app banner rather
        // than a fallback local notification (#45). Balanced below.
        if !isObservingPurchaseFeedback {
            isObservingPurchaseFeedback = true
            StoreKitService.shared.beginObservingPurchaseFeedback()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        autoResumeTimer?.invalidate()
        autoResumeTimer = nil
        countdownTimer?.invalidate()
        countdownTimer = nil
        if isObservingPurchaseFeedback {
            isObservingPurchaseFeedback = false
            StoreKitService.shared.endObservingPurchaseFeedback()
        }

        // Resume audio + escalation unless we got here via success path —
        // the host VC may have already torn down the firing flow on success.
        if successAmount == nil {
            AudioService.shared.resumeAlarmSound()
            AlarmFiringCoordinator.shared.resumeEscalation()
        }
        onDismiss?()
    }

    // MARK: - Setup

    private func setupUI() {
        // Header column (`SPTopUp.jsx:135-142`): a pulsing warn dot + caps
        // pause countdown on top, then the h2 «Пополнить баланс». Close X sits
        // top-right of the row.

        // Subtitle derived from the live snooze price (#548). It used to read
        // "Минимум — 149 ₽ на следующее откладывание", naming the cheapest SKU
        // while claiming it was the amount a snooze needs — two different
        // numbers at every price except exactly 149 ₽.
        subtitleLabel.text = FiringTopUpCopy.subtitle(
            amounts: presets.map(\.amount),
            balance: currentBalance,
            price: snoozePrice
        )

        let pauseRow = UIStackView(arrangedSubviews: [pauseDot, pauseLabel])
        pauseRow.translatesAutoresizingMaskIntoConstraints = false
        pauseRow.axis = .horizontal
        pauseRow.spacing = AppSpacing.sp2   // 8pt — matches the JSX `gap: 8`
        pauseRow.alignment = .center

        let headerLeftStack = UIStackView(arrangedSubviews: [pauseRow, titleH2Label])
        headerLeftStack.translatesAutoresizingMaskIntoConstraints = false
        headerLeftStack.axis = .vertical
        headerLeftStack.spacing = AppSpacing.sp2   // 8pt between caps row and h2
        headerLeftStack.alignment = .leading

        let headerRow = UIStackView(arrangedSubviews: [headerLeftStack, closeButton])
        headerRow.translatesAutoresizingMaskIntoConstraints = false
        headerRow.axis = .horizontal
        headerRow.alignment = .top
        headerRow.distribution = .equalSpacing

        startPauseDotPulse()

        view.addSubview(dragHandle)
        view.addSubview(headerRow)
        view.addSubview(subtitleLabel)
        view.addSubview(presetStack)
        view.addSubview(applePayButton)
        view.addSubview(footerMetaLabel)
        view.addSubview(successContainer)

        successContainer.addSubview(successCheck)
        successContainer.addSubview(successAmountLabel)
        successContainer.addSubview(successCaption)

        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        activateConstraints(headerRow: headerRow)
    }

    /// Pin every subview to its final geometry. Split out of `setupUI` so
    /// neither function trips SwiftLint's `function_body_length` cap.
    private func activateConstraints(headerRow: UIStackView) {
        let inset = AppSpacing.sp5  // 20pt

        NSLayoutConstraint.activate([
            // Drag handle
            dragHandle.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            dragHandle.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            dragHandle.widthAnchor.constraint(equalToConstant: 36),
            dragHandle.heightAnchor.constraint(equalToConstant: 4),

            // Header row
            headerRow.topAnchor.constraint(equalTo: dragHandle.bottomAnchor, constant: AppSpacing.sp4),
            headerRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: inset),
            headerRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -inset),

            closeButton.widthAnchor.constraint(equalToConstant: 32),
            closeButton.heightAnchor.constraint(equalToConstant: 32),

            pauseDot.widthAnchor.constraint(equalToConstant: 8),
            pauseDot.heightAnchor.constraint(equalToConstant: 8),

            // Subtitle
            subtitleLabel.topAnchor.constraint(equalTo: headerRow.bottomAnchor, constant: AppSpacing.sp2),
            subtitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: inset),
            subtitleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -inset),

            // Preset tiles
            presetStack.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: AppSpacing.sp4),
            presetStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: inset),
            presetStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -inset),

            // Apple Pay
            applePayButton.topAnchor.constraint(equalTo: presetStack.bottomAnchor, constant: AppSpacing.sp4),
            applePayButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: inset),
            applePayButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -inset),

            // Footer meta
            footerMetaLabel.topAnchor.constraint(equalTo: applePayButton.bottomAnchor, constant: AppSpacing.sp3),
            footerMetaLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: inset),
            footerMetaLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -inset)
        ])

        activateSuccessConstraints(inset: inset)
    }

    /// Pin the post-purchase success overlay. Kept separate so the main
    /// constraint activation reads top-to-bottom without intermixing the
    /// always-mounted overlay block.
    private func activateSuccessConstraints(inset: CGFloat) {
        NSLayoutConstraint.activate([
            successContainer.topAnchor.constraint(equalTo: view.topAnchor),
            successContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            successContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            successContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            successCheck.centerXAnchor.constraint(equalTo: successContainer.centerXAnchor),
            successCheck.centerYAnchor.constraint(equalTo: successContainer.centerYAnchor, constant: -40),
            successCheck.widthAnchor.constraint(equalToConstant: 96),
            successCheck.heightAnchor.constraint(equalToConstant: 96),

            successAmountLabel.topAnchor.constraint(equalTo: successCheck.bottomAnchor, constant: AppSpacing.sp5),
            successAmountLabel.leadingAnchor.constraint(equalTo: successContainer.leadingAnchor, constant: inset),
            successAmountLabel.trailingAnchor.constraint(equalTo: successContainer.trailingAnchor, constant: -inset),

            successCaption.topAnchor.constraint(equalTo: successAmountLabel.bottomAnchor, constant: AppSpacing.sp3),
            successCaption.leadingAnchor.constraint(equalTo: successContainer.leadingAnchor, constant: inset),
            successCaption.trailingAnchor.constraint(equalTo: successContainer.trailingAnchor, constant: -inset)
        ])
    }

    private func setupPresetTiles() {
        for preset in presets {
            let row = FiringTopUpPresetRow(
                title: FiringTopUpCopy.rowTitle(
                    topUp: preset.amount, balance: currentBalance, price: snoozePrice
                ),
                hint: FiringTopUpCopy.rowHint(
                    topUp: preset.amount, balance: currentBalance, price: snoozePrice
                ),
                amount: preset.amount,
                selected: preset.amount == selectedAmount,
                insufficient: !FiringTopUpCopy.isSufficient(
                    topUp: preset.amount, balance: currentBalance, price: snoozePrice
                )
            ) { [weak self] in
                self?.selectAmount(preset.amount)
            }
            presetStack.addArrangedSubview(row)
            presetRows.append(row)
        }
    }

    /// Build a fresh Apple Pay button for the supplied amount. SPButton's
    /// title / suffix are immutable post-init, so selection changes rebuild
    /// the button instance. Cheap — three presets, max three swaps.
    private func makeApplePayButton(amount: Int) -> SPButton {
        let button = SPButton(
            title: "Apple Pay",
            variant: .money,
            size: .lg,
            icon: UIImage(systemName: "applelogo"),
            suffix: MoneyFormatter.string(amount),
            fullWidth: true
        )
        button.addTarget(self, action: #selector(applePayTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    // MARK: - StoreKit observers

    private func observePurchaseNotifications() {
        let center = NotificationCenter.default
        // Capture the userInfo keys into local lets so the closure isn't
        // forced to read main-actor-isolated `StoreKitService.*UserInfoKey`
        // statics at notification-delivery time (which would emit a
        // @Sendable closure warning under Swift 6 concurrency).
        let amountKey = StoreKitService.amountUserInfoKey
        let messageKey = StoreKitService.messageUserInfoKey
        purchaseCompletedObserver = center.addObserver(
            forName: StoreKitService.purchaseCompletedNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let amount = note.userInfo?[amountKey] as? Double ?? 0
            self.handlePurchaseSuccess(amount: Int(amount.rounded()))
        }
        purchaseFailedObserver = center.addObserver(
            forName: StoreKitService.purchaseFailedNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let message = note.userInfo?[messageKey] as? String
            self.handlePurchaseFailure(message: message)
        }
    }
}

// MARK: - Selection / Actions

extension FiringTopUpBottomSheetViewController {

    private func selectAmount(_ amount: Int) {
        guard amount != selectedAmount else { return }
        selectedAmount = amount
        for (row, preset) in zip(presetRows, presets) {
            row.isSelected = preset.amount == amount
        }
        rebuildApplePayButton()
    }

    private func rebuildApplePayButton() {
        let oldButton = applePayButton
        let newButton = makeApplePayButton(amount: selectedAmount)
        view.insertSubview(newButton, aboveSubview: oldButton)
        NSLayoutConstraint.activate([
            newButton.topAnchor.constraint(equalTo: presetStack.bottomAnchor, constant: AppSpacing.sp4),
            newButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: AppSpacing.sp5),
            newButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -AppSpacing.sp5)
        ])
        // Re-pin the footer meta below the replacement so it stays anchored.
        footerMetaLabel.topAnchor.constraint(equalTo: newButton.bottomAnchor, constant: AppSpacing.sp3).isActive = true
        oldButton.removeFromSuperview()
        applePayButton = newButton
    }

    // MARK: - Actions

    @objc private func applePayTapped() {
        guard !purchaseInFlight else { return }
        purchaseInFlight = true
        applePayButton.isEnabled = false

        guard let preset = presets.first(where: { $0.amount == selectedAmount }) else {
            purchaseInFlight = false
            applePayButton.isEnabled = true
            return
        }

        if let product = StoreKitService.shared.products.first(where: { $0.id == preset.productID }) {
            // Foreign storefront: refuse before `purchase(_:)`, while refusing
            // is still free (#563).
            if let blocked = ForeignCurrencyNotice.blockingMessage(for: product) {
                purchaseInFlight = false
                applePayButton.isEnabled = true
                present(ForeignCurrencyNotice.alert(message: blocked), animated: true)
                return
            }
            Task { @MainActor in
                await StoreKitService.shared.purchase(product)
            }
        } else {
            let pid = preset.productID
            #if DEBUG
            // DEBUG/simulator without a loaded StoreKit catalogue: credit
            // locally so the flow stays testable without ASC products.
            AppLogger.storeKit.notice(
                "FiringTopUpSheet: product \(pid, privacy: .public) not loaded — DEBUG fallback to BalanceService.topUp"
            )
            let amount = Double(preset.amount)
            if BalanceService.shared.topUp(amount: amount) {
                handlePurchaseSuccess(amount: preset.amount)
            } else {
                handlePurchaseFailure(message: StoreKitService.ledgerLockedFailureMessage)
            }
            #else
            // Release: never credit without a real StoreKit transaction.
            AppLogger.storeKit.error(
                "FiringTopUpSheet: product \(pid, privacy: .public) not loaded — purchase unavailable (no local credit in release)"
            )
            handlePurchaseFailure(message: "Не удалось загрузить пакеты пополнения. Попробуйте позже.")
            #endif
        }
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    // MARK: - Success / failure

    private func handlePurchaseSuccess(amount: Int) {
        // Multiple StoreKit pathways (foreground purchase, background
        // Transaction.updates) can both post `purchaseCompletedNotification`.
        // Guard against showing the success state twice.
        guard successAmount == nil else { return }
        successAmount = amount
        purchaseInFlight = false

        successAmountLabel.attributedText = MoneyFormatter.attributed(
            Decimal(amount), digitsFont: AppTypography.moneyXl, prefix: "+"
        )
        successContainer.isHidden = false
        UIView.animate(withDuration: SPSupport.durationBase) {
            self.titleH2Label.alpha = 0
            self.pauseDot.alpha = 0
            self.pauseLabel.alpha = 0
            self.subtitleLabel.alpha = 0
            self.presetStack.alpha = 0
            self.applePayButton.alpha = 0
            self.footerMetaLabel.alpha = 0
        }

        autoResumeTimer?.invalidate()
        autoResumeTimer = nil
        countdownTimer?.invalidate()
        countdownTimer = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.dismiss(animated: true)
        }
    }

    private func handlePurchaseFailure(message: String?) {
        purchaseInFlight = false
        applePayButton.isEnabled = true

        let alert = UIAlertController(
            title: "Покупка не выполнена",
            message: message ?? "Попробуйте ещё раз.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Ок", style: .default))
        present(alert, animated: true)
    }

    // MARK: - Auto-resume timer

    private func startAutoResumeTimer() {
        autoResumeTimer?.invalidate()
        autoResumeTimer = Timer.scheduledTimer(
            withTimeInterval: autoResumeTimeout,
            repeats: false
        ) { [weak self] _ in
            self?.handleAutoResume()
        }
    }

    private func handleAutoResume() {
        // Don't yank the sheet away if the user is mid-purchase — the StoreKit
        // sheet may still be on screen, and dismissing the host would orphan
        // the transaction.
        guard !purchaseInFlight, successAmount == nil else { return }
        AppLogger.coordinator.notice("FiringTopUpSheet: 60s auto-resume — closing without purchase")
        dismiss(animated: true)
    }

    private func startCountdownTimer() {
        remainingSeconds = Int(autoResumeTimeout)
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.remainingSeconds = max(0, self.remainingSeconds - 1)
            self.updatePauseLabel()
        }
    }

    /// 0.4 → 1.0 opacity autoreverse pulse on the warn dot, 1.6s each leg —
    /// matches the `sp-pulse` keyframe the JSX warn dot rides (`SPTopUp.jsx:
    /// 136`). CABasicAnimation so it keeps running through UIKit interactions.
    private func startPauseDotPulse() {
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.4
        pulse.toValue = 1.0
        pulse.duration = 1.6
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pauseDot.layer.add(pulse, forKey: "pauseDotPulse")
    }

    private func updatePauseLabel() {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        let countdown = String(format: "%02d:%02d", minutes, seconds)
        // Caps «Будильник на паузе · MM:SS» per `SPTopUp.jsx:137`.
        let attributed = NSAttributedString(
            string: "Будильник на паузе · \(countdown)".uppercased(),
            attributes: [
                .font: AppTypography.caps.monospacedDigit(),
                .kern: AppTypography.capsKerning,
                .foregroundColor: AppColors.warn300
            ]
        )
        pauseLabel.attributedText = attributed
    }
}
