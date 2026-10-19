import StoreKit
import UIKit
import os

/// Bottom-sheet presented over `AlarmFiringViewController` when the user wants
/// to top up the wallet mid-alarm so they can keep snoozing.
///
/// V2 spec: `FiringTopUpPresets`,
/// `docs/design/snoozepay-2026-04-27/project/components/SPTopUp.jsx:103-197` contains "function FiringTopUpPresets".
/// Three vertical preset rows feed a single Apple Pay primary CTA; each row's
/// price is the actual storefront offer of its mapped SKU. Visuals match
/// the V2 design system — bg1 surface, 28pt
/// top corners, a pulsing warn dot + caps «Будильник на паузе · MM:SS» + h2
/// «Пополнить баланс» header, full-width preset rows, money-toned Apple Pay
/// button, footer meta.
///
/// Side effects beyond pixel layout:
/// - On `viewWillAppear` the alarm audio + escalation timer are paused via
///   `AudioService.pauseAlarmSound()`. A 60-second auto-resume timer starts
///   so an abandoned sheet can't keep the alarm silent indefinitely.
/// - On a successful purchase the controller flips to a green-checkmark
///   credited amount/currency success state and auto-dismisses after 2 seconds.
/// - On dismissal (any path: cancel, success-auto, 60s-timeout) the audio
///   resumes unless the alarm was already stopped externally.
final class FiringTopUpBottomSheetViewController: UIViewController {

    // MARK: - Preset model

    /// SKU identity and its historical RUB amount, used only by the explicit
    /// empty-catalog UI-tour demo. Paid prices always come from TopUpOffer.
    struct Preset {
        let rubDemoAmount: Int
        let popular: Bool
        let productID: String

        init?(productID: String, popular: Bool) {
            guard let nominal = StoreKitService.catalogAmount(for: productID) else { return nil }
            rubDemoAmount = nominal
            self.popular = popular
            self.productID = productID
        }
    }

    static let defaultPresets: [Preset] = [
        Preset(productID: "io.mobilife.snoozepay.balance.149", popular: false),
        Preset(productID: "io.mobilife.snoozepay.balance.499", popular: true),
        Preset(productID: "io.mobilife.snoozepay.balance.999", popular: false)
    ].compactMap { $0 }

    // MARK: - Configuration

    private let presets: [Preset]

    /// One next charge, used only to recommend an actual compatible offer.
    /// Unknown arithmetic never produces an affordability claim.
    private let snoozePrice: Double

    private let balance: BalanceService

    /// Auto-resume timeout. Spec is 60 seconds. Stored as a constant so the
    /// controller doesn't re-read a magic literal across timer setup, label
    /// seed, and countdown formatting.
    private let autoResumeTimeout: TimeInterval = 60

    /// Fired when the sheet is dismissed for any reason. Owner uses this to
    /// resume the escalation timer / refresh snooze affordance.
    var onDismiss: (() -> Void)?

    // MARK: - State

    private var selectedProductID: String?
    private var hasUserSelection = false
    private let offerProvider: ((String) -> TopUpOffer?)?
    private let launchArguments: [String]
    private var productsLoadedObserver: NSObjectProtocol?
    private var purchaseButtonConstraints: [NSLayoutConstraint] = []

    /// Set to true once we've kicked off Apple Pay so the auto-resume timer
    /// doesn't yank the sheet out from under the StoreKit dialog.
    private var purchaseInFlight: Bool = false

    /// Flips when StoreKit reports a successful credit. Drives the success
    /// state UI swap + the 2-second auto-dismiss timer.
    private var successReceipt: TopUpSuccessReceipt?

    /// Original auto-resume timeout timer (60s). Cleared when the pause ends;
    /// an attempted interactive dismissal must not replace its deadline.
    private var autoResumeTimer: Timer?
    private var autoResumeDeadlineExpired = false
    private var failureAcknowledgementPending = false
    private var pauseEnded = false
    private var pauseStarted = false

    /// The actual scheduled deadline, retained across a cancelled interactive dismissal.
    var autoResumeFireDate: Date? { autoResumeTimer?.fireDate }

    /// Tests drive real lifecycle callbacks without touching shared audio or feedback state.
    private let pauseLifecycle: ((Bool) -> Void)?
    private let preflightRefusal: ((String) -> String?)?

    /// Visible mm:ss countdown reflected in the pause label. Decremented every
    /// 1s so the user can see how long they have left to commit.
    private var remainingSeconds: Int

    /// 1Hz countdown timer feeding `pauseLabel`.
    private var countdownTimer: Timer?

    /// Notification observer tokens torn down in `deinit`.
    private var purchaseCompletedObserver: NSObjectProtocol?
    private var purchaseFailedObserver: NSObjectProtocol?
    private var purchaseCancelledObserver: NSObjectProtocol?
    /// Optional product dispatch keeps this real form testable without an App Store catalogue.
    private let purchaseProduct: ((String) -> Void)?
    private let notificationCenter: NotificationCenter
    private let scheduleSuccessDismissal: TopUpSuccessDismissal
    /// Narrow UI endpoints let lifecycle tests inspect the real alert and dismiss request.
    private let presentPurchaseFailure: ((UIAlertController) -> Void)?
    private let dismissForAutoResume: (() -> Void)?
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

    /// h2 «Пополнить баланс» header
    /// (`docs/design/snoozepay-2026-04-27/project/components/SPTopUp.jsx:139` contains "Пополнить баланс").
    private let titleH2Label: UILabel = {
        let label = UILabel()
        label.font = AppTypography.h2
        label.textColor = .white
        label.text = Localized.text("firing.top_up.title")
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    /// 8pt warn dot to the left of the pause caps
    /// (`docs/design/snoozepay-2026-04-27/project/components/SPTopUp.jsx:136` contains "width: 8, height: 8").
    /// Static in the design; the pulse is ours (`startPauseDotPulse()`).
    private let pauseDot: UIView = {
        let view = UIView()
        view.backgroundColor = AppColors.warn400
        view.layer.cornerRadius = 4
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    /// Caps pause countdown «Будильник на паузе · 00:54»
    /// (`docs/design/snoozepay-2026-04-27/project/components/SPTopUp.jsx:137` contains "Будильник на паузе").
    private let pauseLabel: UILabel = {
        let label = UILabel()
        label.accessibilityIdentifier = "firingTopUp.pauseCountdown"
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
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    /// Vertical column of full-width preset rows
    /// (`docs/design/snoozepay-2026-04-27/project/components/SPTopUp.jsx:144-175` contains "Пресеты"): each
    /// row shows generic package copy, the actual price and a selection chip.
    private var presetRows: [FiringTopUpPresetRow] = []
    private let presetStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = AppSpacing.sp2
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    /// Apple Pay primary CTA. Money tone with applelogo icon + suffix that
    /// tracks the selected offer. Selection/catalog refresh replaces this
    /// immutable-title control while retaining one set of active anchors.
    private lazy var applePayButton: SPButton = makeApplePayButton()

    /// A top-up is wallet credit, not a promise that one snooze is now affordable.
    private let footerMetaLabel: UILabel = {
        let label = UILabel()
        label.font = AppTypography.meta
        label.textColor = AppColors.fg3
        label.textAlignment = .center
        label.numberOfLines = 0
        label.text = Localized.text("deposit.disclaimer")
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
        label.accessibilityIdentifier = "firingTopUp.successAmount"
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
        label.text = Localized.text("firing.top_up.success")
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - Init

    init(
        presets: [Preset] = defaultPresets,
        snoozePrice: Double = 0,
        balance: BalanceService = .shared,
        notificationCenter: NotificationCenter = .default,
        scheduleSuccessDismissal: @escaping TopUpSuccessDismissal = { delay, action in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { action() }
        },
        purchaseProduct: ((String) -> Void)? = nil,
        presentPurchaseFailure: ((UIAlertController) -> Void)? = nil,
        dismissForAutoResume: (() -> Void)? = nil,
        pauseLifecycle: ((Bool) -> Void)? = nil,
        preflightRefusal: ((String) -> String?)? = nil,
        offerProvider: ((String) -> TopUpOffer?)? = nil,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        self.presets = presets
        self.offerProvider = offerProvider
        self.launchArguments = arguments
        self.balance = balance
        self.purchaseProduct = purchaseProduct
        self.notificationCenter = notificationCenter
        self.scheduleSuccessDismissal = scheduleSuccessDismissal
        self.presentPurchaseFailure = presentPurchaseFailure
        self.dismissForAutoResume = dismissForAutoResume
        self.pauseLifecycle = pauseLifecycle
        self.preflightRefusal = preflightRefusal
        self.snoozePrice = snoozePrice
        self.selectedProductID = presets.first?.productID
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
        if let token = productsLoadedObserver { notificationCenter.removeObserver(token) }
        if let token = purchaseCompletedObserver {
            notificationCenter.removeObserver(token)
        }
        if let token = purchaseFailedObserver {
            notificationCenter.removeObserver(token)
        }
        if let token = purchaseCancelledObserver {
            notificationCenter.removeObserver(token)
        }
        autoResumeTimer?.invalidate()
        countdownTimer?.invalidate()
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        // Sheet surface bg1 (#288):
        // `docs/design/snoozepay-2026-04-27/project/components/SPTopUp.jsx:127` contains "var(--sp-bg-1)".
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
        guard !pauseEnded else { return }
        // A cancelled interactive dismissal reappears on the same original pause.
        if !pauseStarted {
            pauseStarted = true
            updatePauseLifecycle(active: true)
            startAutoResumeTimer()
            startCountdownTimer()
        }
        updatePauseLabel()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Cancelled gestures and temporary full-screen covers do not end this pause.
        guard isBeingDismissed || isMovingFromParent || (presentingViewController == nil && parent == nil) else {
            return
        }
        endPauseTimers()
        updatePauseLifecycle(active: false)
        onDismiss?()
    }

    private func updatePauseLifecycle(active: Bool) {
        if let pauseLifecycle {
            pauseLifecycle(active)
            return
        }
        if active {
            AudioService.shared.pauseAlarmSound()
            AlarmFiringCoordinator.shared.pauseEscalation()
            if !isObservingPurchaseFeedback {
                isObservingPurchaseFeedback = true
                StoreKitService.shared.beginObservingPurchaseFeedback()
            }
        } else {
            if isObservingPurchaseFeedback {
                isObservingPurchaseFeedback = false
                StoreKitService.shared.endObservingPurchaseFeedback()
            }
            if successReceipt == nil {
                AudioService.shared.resumeAlarmSound()
                AlarmFiringCoordinator.shared.resumeEscalation()
            }
        }
    }

    // MARK: - Setup

    private func setupUI() {
        // Header column
        // (`docs/design/snoozepay-2026-04-27/project/components/SPTopUp.jsx:135-142` contains "Пополнить баланс"):
        // a warn dot + caps pause countdown on top, then the h2 «Пополнить
        // баланс». Close X sits top-right of the row. The dot is static in
        // the design; the app pulses it (`startPauseDotPulse()`).

        subtitleLabel.text = Localized.text("deposit.disclaimer")

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

            // Footer meta
            footerMetaLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: inset),
            footerMetaLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -inset)
        ])

        pinPurchaseButton()
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
            let row = FiringTopUpPresetRow(title: Localized.text("firing.top_up.row.title.generic"), hint: "",
                                          displayPrice: "—", selected: false) { [weak self] in
                self?.selectProduct(preset.productID)
            }
            row.accessibilityIdentifier = "firingTopUp.preset." + preset.productID
            presetStack.addArrangedSubview(row)
            presetRows.append(row)
        }
        refreshCatalog()
    }

    private func makeApplePayButton() -> SPButton {
        let offer = selectedOffer
        let price = offer?.displayPrice ?? "—"
        let button = SPButton(title: "Apple Pay", variant: .money, size: .lg,
                              icon: UIImage(systemName: "applelogo"), suffix: price, fullWidth: true)
        button.accessibilityIdentifier = "firingTopUp.purchaseButton"
        button.accessibilityLabel = "Apple Pay, " + price
        button.isEnabled = canPurchase && offer != nil
        button.alpha = successReceipt == nil ? 1 : 0
        button.addTarget(self, action: #selector(applePayTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    private var canPurchase: Bool { !purchaseInFlight && canSelectProduct }

    /// A pending purchase blocks dispatch, but a new SKU remains selected for retry after cancellation.
    private var canSelectProduct: Bool {
        successReceipt == nil && !failureAcknowledgementPending && !pauseEnded
    }

    private var selectedOffer: TopUpOffer? { selectedProductID.flatMap { offer(for: $0) } }

    private var usesDemoCatalog: Bool {
        #if DEBUG
        return offerProvider == nil && StoreKitService.isCatalogForcedEmpty(arguments: launchArguments)
        #else
        return false
        #endif
    }

    private func offer(for productID: String) -> TopUpOffer? {
        guard let preset = presets.first(where: { $0.productID == productID }) else { return nil }
        if let offerProvider {
            let offer = offerProvider(productID)
            return offer?.productID == productID ? offer : nil
        }
        #if DEBUG
        if usesDemoCatalog {
            return TopUpOffer(productID: productID, price: Decimal(preset.rubDemoAmount), currencyCode: "RUB",
                              displayPrice: MoneyFormatter.string(preset.rubDemoAmount))
        }
        #endif
        return StoreKitService.shared.products.first { $0.id == productID }.flatMap { TopUpOffer(product: $0) }
    }

    private func refreshCatalog() {
        let offers = presets.compactMap { offer(for: $0.productID) }
        if !hasUserSelection && canPurchase {
            let compatible = offers.filter { balance.acceptsPurchase(in: $0.currency) }
            selectedProductID = FiringTopUpCopy.recommendedProductID(
                offers: compatible, balance: balance.balance, price: snoozePrice, walletCurrency: balance.walletCurrency
            ) ?? offers.first?.productID ?? presets.first?.productID
        }
        for (row, preset) in zip(presetRows, presets) {
            let offer = offers.first { $0.productID == preset.productID }
            row.update(title: Localized.text("firing.top_up.row.title.generic"), hint: "",
                       displayPrice: offer?.displayPrice ?? "—", selected: preset.productID == selectedProductID,
                       insufficient: offer.map {
                           FiringTopUpCopy.coversNextCharge(offer: $0, balance: balance.balance, price: snoozePrice,
                                                          walletCurrency: balance.walletCurrency) == false
                       } ?? false)
        }
        rebuildApplePayButton()
        updatePurchaseAvailability()
    }

    private func updatePurchaseAvailability() {
        applePayButton.isEnabled = canPurchase && selectedOffer != nil
        // SPButton refreshes its disabled alpha even when isEnabled stays false.
        if successReceipt != nil { applePayButton.alpha = 0 }
        for (row, preset) in zip(presetRows, presets) {
            row.isEnabled = canSelectProduct && offer(for: preset.productID) != nil
        }
    }

    // MARK: - StoreKit observers

    private func observePurchaseNotifications() {
        let center = notificationCenter
        productsLoadedObserver = center.addObserver(
            forName: StoreKitService.productsLoadedNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refreshCatalog() }
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
            guard let receipt = TopUpSuccessReceipt(eventAmount: note.userInfo?[amountKey],
                                                    currency: self.balance.walletCurrency) else {
                AppLogger.storeKit.error("FiringTopUpSheet: invalid credited amount event — ignoring")
                return
            }
            self.handlePurchaseSuccess(receipt)
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
        purchaseCancelledObserver = center.addObserver(
            forName: StoreKitService.purchaseCancelledNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, !self.pauseEnded, self.purchaseInFlight, self.successReceipt == nil else { return }
            self.purchaseInFlight = false
            self.resumeIfDeadlineExpired()
            self.updatePurchaseAvailability()
        }
    }
}

// MARK: - Selection / Actions

extension FiringTopUpBottomSheetViewController {

    private func selectProduct(_ productID: String) {
        guard canSelectProduct, offer(for: productID) != nil else { return }
        hasUserSelection = true
        selectedProductID = productID
        refreshCatalog()
    }

    private func pinPurchaseButton() {
        purchaseButtonConstraints = [
            applePayButton.topAnchor.constraint(equalTo: presetStack.bottomAnchor, constant: AppSpacing.sp4),
            applePayButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: AppSpacing.sp5),
            applePayButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -AppSpacing.sp5),
            footerMetaLabel.topAnchor.constraint(equalTo: applePayButton.bottomAnchor, constant: AppSpacing.sp3)
        ]
        NSLayoutConstraint.activate(purchaseButtonConstraints)
    }

    private func rebuildApplePayButton() {
        NSLayoutConstraint.deactivate(purchaseButtonConstraints)
        applePayButton.removeFromSuperview()
        applePayButton = makeApplePayButton()
        view.insertSubview(applePayButton, belowSubview: footerMetaLabel)
        pinPurchaseButton()
    }

    // MARK: - Actions

    @objc private func applePayTapped() {
        guard canPurchase else { return }
        guard let offer = selectedOffer else { refreshCatalog(); return }
        // The real wallet policy precedes both test dispatch and optional refusals.
        let refusal = balance.acceptsPurchase(in: offer.currency)
            ? preflightRefusal?(offer.productID)
            : ForeignCurrencyNotice.message(wallet: balance.walletCurrency, storefront: offer.currency)
        if let refusal {
            handlePurchaseFailure(message: refusal, title: ForeignCurrencyNotice.alertTitle,
                                  dismissTitle: Localized.text("deposit.foreign_currency.dismiss"))
            return
        }
        purchaseInFlight = true
        updatePurchaseAvailability()
        if let purchaseProduct { purchaseProduct(offer.productID); return }
        #if DEBUG
        if usesDemoCatalog, let preset = presets.first(where: { $0.productID == offer.productID }) {
            let amount = Double(preset.rubDemoAmount)
            if balance.topUp(amount: amount), let receipt = TopUpSuccessReceipt(amount: amount, currency: .rub) {
                handlePurchaseSuccess(receipt)
            } else {
                handlePurchaseFailure(message: StoreKitService.ledgerLockedFailureMessage)
            }
            return
        }
        #endif
        guard offerProvider == nil,
              let product = StoreKitService.shared.products.first(where: { $0.id == offer.productID }) else {
            handlePurchaseFailure(message: Localized.text("deposit.error.products_unavailable"))
            return
        }
        Task { @MainActor in await StoreKitService.shared.purchase(product) }
    }

    @objc private func closeTapped() {
        endPauseTimers()
        dismiss(animated: true)
    }

    // MARK: - Success / failure

    private func handlePurchaseSuccess(_ receipt: TopUpSuccessReceipt) {
        // Multiple StoreKit pathways (foreground purchase, background
        // Transaction.updates) can both post `purchaseCompletedNotification`.
        // Guard against showing the success state twice.
        guard !pauseEnded, successReceipt == nil else { return }
        successReceipt = receipt
        purchaseInFlight = false

        successAmountLabel.attributedText = MoneyFormatter.attributed(
            receipt.amount, currency: receipt.currency, digitsFont: AppTypography.moneyXl, prefix: "+"
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

        endPauseTimers()

        scheduleSuccessDismissal(2) { [weak self] in
            self?.dismiss(animated: true)
        }
    }

    private func handlePurchaseFailure(message: String?, title: String? = nil, dismissTitle: String? = nil) {
        guard !pauseEnded, successReceipt == nil, !failureAcknowledgementPending else { return }
        failureAcknowledgementPending = true
        purchaseInFlight = false
        updatePurchaseAvailability()

        let alert = UIAlertController(
            title: title ?? Localized.text("firing.alert.purchase_failed.title"),
            message: message ?? Localized.text("firing.alert.purchase_failed.message"),
            preferredStyle: .alert
        )
        let acknowledge = UIAlertAction(
            title: dismissTitle ?? Localized.text("common.button.ok"), style: .default
        ) { [weak self, weak alert] _ in
            // Resume only after the alert is gone; dismissing the presenter while
            // it still owns the alert would dismiss that alert instead of the sheet.
            guard let alert else {
                self?.acknowledgePurchaseFailure()
                return
            }
            alert.dismiss(animated: true) { [weak self] in self?.acknowledgePurchaseFailure() }
        }
        alert.addAction(acknowledge)
        if let presentPurchaseFailure {
            presentPurchaseFailure(alert)
        } else {
            present(alert, animated: true)
        }
    }

    /// Also called by the real error alert's OK action after its dismissal completes.
    func acknowledgePurchaseFailure() {
        guard !pauseEnded, failureAcknowledgementPending else { return }
        failureAcknowledgementPending = false
        resumeIfDeadlineExpired()
        updatePurchaseAvailability()
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

    /// The actual timer callback is also directly driveable without waiting 60 seconds.
    func handleAutoResume() {
        guard !pauseEnded, successReceipt == nil else { return }
        autoResumeTimer?.invalidate()
        autoResumeTimer = nil
        countdownTimer?.invalidate()
        countdownTimer = nil
        autoResumeDeadlineExpired = true
        remainingSeconds = 0
        updatePauseLabel()
        resumeIfDeadlineExpired()
    }

    private func resumeIfDeadlineExpired() {
        // Keep the original deadline pending through StoreKit or the terminal
        // error's OK action. Neither cancellation nor failure starts another 60s.
        guard !pauseEnded, successReceipt == nil, autoResumeDeadlineExpired,
              !purchaseInFlight, !failureAcknowledgementPending else { return }
        endPauseTimers()
        AppLogger.coordinator.notice("FiringTopUpSheet: 60s auto-resume — closing without purchase")
        if let dismissForAutoResume {
            dismissForAutoResume()
        } else {
            dismiss(animated: true)
        }
    }

    /// Shared by manual dismissal, lifecycle teardown, success, and auto-resume.
    func endPauseTimers() {
        pauseEnded = true
        autoResumeDeadlineExpired = false
        failureAcknowledgementPending = false
        purchaseInFlight = false
        autoResumeTimer?.invalidate()
        autoResumeTimer = nil
        countdownTimer?.invalidate()
        countdownTimer = nil
        if isViewLoaded { updatePurchaseAvailability() }
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
    /// borrows the 1.6s cadence of the prototype's `PulseDot`
    /// (`docs/design/snoozepay-2026-04-27/project/components/SPScreensV2.jsx:29` contains "sp-pulse 1.6s").
    /// The top-up sheet's own dot is static in the prototype
    /// (`docs/design/snoozepay-2026-04-27/project/components/SPTopUp.jsx:136` contains "width: 8, height: 8").
    /// CABasicAnimation so it keeps running through UIKit interactions.
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
        // Caps «Будильник на паузе · MM:SS» per
        // `docs/design/snoozepay-2026-04-27/project/components/SPTopUp.jsx:137` contains "Будильник на паузе".
        let attributed = NSAttributedString(
            // `.uppercased()` stays at the call site: the catalogue holds
            // the sentence, the caps face is presentation.
            string: Localized.format("firing.top_up.pause", countdown).uppercased(),
            attributes: [
                .font: AppTypography.caps.monospacedDigit(),
                .kern: AppTypography.capsKerning,
                .foregroundColor: AppColors.warn300
            ]
        )
        pauseLabel.attributedText = attributed
    }
}
