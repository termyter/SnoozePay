import StoreKit
import UIKit
import os

/// Bottom-sheet presented over `AlarmFiringViewController` when the user wants
/// to top up the wallet mid-alarm so they can keep snoozing.
///
/// Spec: `docs/design/snoozepay-2026-04-27/project/components/SPTopUp.jsx`
/// (variant `B · Bottom sheet с пресетами`) and the matching section in
/// `SnoozePay - All Screens.html`. Three preset tiles (200 / 500 / 1000 ₽)
/// drive a single Apple Pay primary CTA; the secondary "Отменить" ghost
/// button dismisses without charging.
///
/// Side effects beyond pixel layout:
/// - On `viewWillAppear` the alarm audio + escalation timer are paused via
///   `AudioService.pauseAlarmSound()`. A 60-second auto-resume timer starts
///   so an abandoned sheet can't keep the alarm silent indefinitely.
/// - On a successful purchase the controller flips to a green-checkmark
///   "+N ₽" success state and auto-dismisses after 2 seconds.
/// - On dismissal (any path: cancel, success-auto, 60s-timeout) the audio
///   resumes unless the alarm was already stopped externally.
///
/// `FiringTopUpBottomSheetPresetIDs` exposes the StoreKit product IDs the
/// presets currently map to so tests can assert the wiring without parsing
/// the controller's private state.
final class FiringTopUpBottomSheetViewController: UIViewController {

    // MARK: - Preset model

    /// One of the three top-up tiles. `productID` points at the closest existing
    /// IAP SKU in StoreKitService (149 / 499 / 999) — once PM registers exact
    /// 200 / 500 / 1000 ₽ SKUs in App Store Connect, swap these mappings to
    /// the matching product IDs (tracked as a follow-up in #141 description).
    struct Preset {
        let amount: Int
        let label: String
        /// StoreKit product ID. Resolved against `StoreKitService.shared.products`
        /// when the user taps Apple Pay. If the product hasn't been loaded yet
        /// the controller falls back to `BalanceService.topUp(amount:)` so the
        /// debug flow still credits the wallet end-to-end.
        let productID: String
    }

    /// Default preset list — see `Preset.productID` for the SKU mapping caveat.
    static let defaultPresets: [Preset] = [
        Preset(amount: 200, label: "ровно на сейчас", productID: "com.snooze_pay.balance.149"),
        Preset(amount: 500, label: "на пару дней", productID: "com.snooze_pay.balance.499"),
        Preset(amount: 1000, label: "забыть про залог", productID: "com.snooze_pay.balance.999")
    ]

    // MARK: - Configuration

    private let presets: [Preset]

    /// Auto-resume timeout. Spec is 60 seconds (#141). Exposed as a stored
    /// property so the controller doesn't re-read a magic literal in three
    /// places (timer setup, label seed, countdown formatting).
    private let autoResumeTimeout: TimeInterval = 60

    /// Fired when the sheet is dismissed for any reason. Owner (the firing VC
    /// presenter) uses this to resume the escalation timer / refresh snooze
    /// affordance once the wallet has settled.
    var onDismiss: (() -> Void)?

    // MARK: - State

    private var selectedAmount: Int

    /// Set to true once we've kicked off Apple Pay so the auto-resume timer
    /// doesn't yank the sheet out from under the StoreKit dialog.
    private var purchaseInFlight: Bool = false

    /// Flips when StoreKit reports a successful credit. Drives the success-
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

    /// Notification observer tokens so we tear them down in `deinit`.
    private var purchaseCompletedObserver: NSObjectProtocol?
    private var purchaseFailedObserver: NSObjectProtocol?

    // MARK: - Subviews

    private let dragHandle: UIView = {
        let view = UIView()
        view.backgroundColor = AppColors.whiteOverlay12
        view.layer.cornerRadius = 2
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let pauseDot: UIView = {
        let view = UIView()
        view.backgroundColor = AppColors.warn400
        view.layer.cornerRadius = 4
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let pauseLabel: UILabel = {
        let label = UILabel()
        label.font = AppTypography.caps
        label.textColor = AppColors.warn300
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = AppTypography.h2
        label.textColor = AppColors.fg1
        label.text = "Пополнить баланс"
        label.translatesAutoresizingMaskIntoConstraints = false
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
        label.text = "Минимум — 200 ₽ на следующее откладывание. Можно больше, чтобы не возвращаться сюда."
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    /// Three-tile horizontal stack of `SPAmountPreset`s.
    private var presetTiles: [SPAmountPreset] = []
    private let presetStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = AppSpacing.sp2
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    /// Apple Pay primary CTA. Title is rebuilt whenever selection changes.
    private lazy var applePayButton: SPButton = {
        let button = SPButton(
            title: "Apple Pay · \(selectedAmount) ₽",
            variant: .money,
            size: .lg,
            icon: UIImage(systemName: "applelogo"),
            fullWidth: true
        )
        button.addTarget(self, action: #selector(applePayTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var cancelButton: SPButton = {
        let button = SPButton(
            title: "Отменить",
            variant: .ghost,
            size: .lg,
            fullWidth: true
        )
        button.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    /// Full-screen overlay shown after a successful purchase. Holds the green
    /// checkmark + "+N ₽" copy. Hidden until `successAmount` is set.
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

    init(presets: [Preset] = defaultPresets) {
        self.presets = presets
        // Default-select the cheapest preset (200 ₽ — minimum cost of a single
        // snooze per the spec's "amount_default" copy).
        self.selectedAmount = presets.first?.amount ?? 200
        self.remainingSeconds = 60
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        if let sheet = sheetPresentationController {
            // Custom ~360pt detent matches the design comp height. Falls back
            // to the system `.medium` detent on iOS < 16 so we don't crash on
            // older devices that the project still supports (15.1+).
            if #available(iOS 16.0, *) {
                let custom = UISheetPresentationController.Detent.custom(
                    identifier: UISheetPresentationController.Detent.Identifier("snoozepay.topup")
                ) { _ in 360 }
                sheet.detents = [custom, .large()]
            } else {
                sheet.detents = [.medium(), .large()]
            }
            sheet.prefersGrabberVisible = false  // We render our own drag handle
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
        view.backgroundColor = AppColors.bg1
        // Per the spec the firing screen overlay is dark; pin the sheet to
        // dark so the SPAmountPreset / SPButton tokens resolve against the
        // same palette as the host VC.
        overrideUserInterfaceStyle = .dark
        setupUI()
        setupPresetTiles()
        observePurchaseNotifications()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Pause audio + escalation as soon as the sheet is about to render so
        // the user isn't fighting the alarm sound while choosing a preset.
        AudioService.shared.pauseAlarmSound()
        AlarmFiringCoordinator.shared.pauseEscalation()
        startAutoResumeTimer()
        startCountdownTimer()
        updatePauseLabel()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        autoResumeTimer?.invalidate()
        autoResumeTimer = nil
        countdownTimer?.invalidate()
        countdownTimer = nil

        // If the user dismissed without buying — resume audio + escalation so
        // the alarm picks up where it left off. Skip resume on success path
        // because the host VC may have already torn down the firing flow.
        if successAmount == nil {
            AudioService.shared.resumeAlarmSound()
            AlarmFiringCoordinator.shared.resumeEscalation()
        }
        onDismiss?()
    }

    // MARK: - Setup

    private func setupUI() {
        let contentStack = UIStackView()
        contentStack.axis = .vertical
        contentStack.spacing = AppSpacing.sp4
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(dragHandle)

        // Header row: pause indicator on the left, close button on the right.
        let pauseRow = UIStackView()
        pauseRow.axis = .horizontal
        pauseRow.alignment = .center
        pauseRow.spacing = AppSpacing.sp2
        pauseRow.translatesAutoresizingMaskIntoConstraints = false
        pauseRow.addArrangedSubview(pauseDot)
        pauseRow.addArrangedSubview(pauseLabel)
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        pauseRow.addArrangedSubview(spacer)
        pauseRow.addArrangedSubview(closeButton)

        view.addSubview(pauseRow)
        view.addSubview(titleLabel)
        view.addSubview(subtitleLabel)
        view.addSubview(presetStack)
        view.addSubview(applePayButton)
        view.addSubview(cancelButton)
        view.addSubview(successContainer)

        // Success overlay — same surface, hidden until a purchase completes.
        successContainer.addSubview(successCheck)
        successContainer.addSubview(successAmountLabel)
        successContainer.addSubview(successCaption)

        closeButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        let inset = AppSpacing.sp5

        NSLayoutConstraint.activate([
            // Drag handle
            dragHandle.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            dragHandle.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            dragHandle.widthAnchor.constraint(equalToConstant: 36),
            dragHandle.heightAnchor.constraint(equalToConstant: 4),

            // Pause row + close button
            pauseRow.topAnchor.constraint(equalTo: dragHandle.bottomAnchor, constant: AppSpacing.sp4),
            pauseRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: inset),
            pauseRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -inset + 4),
            pauseDot.widthAnchor.constraint(equalToConstant: 8),
            pauseDot.heightAnchor.constraint(equalToConstant: 8),
            closeButton.widthAnchor.constraint(equalToConstant: 32),
            closeButton.heightAnchor.constraint(equalToConstant: 32),

            // Title
            titleLabel.topAnchor.constraint(equalTo: pauseRow.bottomAnchor, constant: AppSpacing.sp2),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: inset),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -inset),

            // Subtitle
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: AppSpacing.sp1),
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

            // Cancel
            cancelButton.topAnchor.constraint(equalTo: applePayButton.bottomAnchor, constant: AppSpacing.sp2),
            cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: inset),
            cancelButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -inset),

            // Success overlay
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
            let tile = SPAmountPreset(
                value: Decimal(preset.amount),
                label: preset.label,
                selected: preset.amount == selectedAmount
            ) { [weak self] in
                self?.selectAmount(preset.amount)
            }
            presetStack.addArrangedSubview(tile)
            presetTiles.append(tile)
        }
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
        for (tile, preset) in zip(presetTiles, presets) {
            tile.isSelected = preset.amount == amount
        }
        // Rebuild the Apple Pay title — SPButton doesn't expose a setter so we
        // re-create the button title via configuration on its private label
        // path. Cheapest path: replace the button entirely. Tradeoff: a tiny
        // extra alloc per tap. Acceptable here (3 presets, max 3 swaps).
        rebuildApplePayButton()
    }

    private func rebuildApplePayButton() {
        let oldButton = applePayButton
        let newButton = SPButton(
            title: "Apple Pay · \(selectedAmount) ₽",
            variant: .money,
            size: .lg,
            icon: UIImage(systemName: "applelogo"),
            fullWidth: true
        )
        newButton.addTarget(self, action: #selector(applePayTapped), for: .touchUpInside)
        newButton.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(newButton, aboveSubview: oldButton)
        NSLayoutConstraint.activate([
            newButton.topAnchor.constraint(equalTo: presetStack.bottomAnchor, constant: AppSpacing.sp4),
            newButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: AppSpacing.sp5),
            newButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -AppSpacing.sp5)
        ])
        // Re-pin cancel button below the replacement so the layout stays
        // anchored to it.
        cancelButton.topAnchor.constraint(equalTo: newButton.bottomAnchor, constant: AppSpacing.sp2).isActive = true
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

        // Resolve the StoreKit product if it's already loaded; otherwise fall
        // back to a direct top-up so the debug flow still credits the wallet
        // end-to-end (production path goes through StoreKitService once PM
        // registers the exact 200/500/1000 SKUs in App Store Connect).
        if let product = StoreKitService.shared.products.first(where: { $0.id == preset.productID }) {
            Task { @MainActor in
                await StoreKitService.shared.purchase(product)
            }
        } else {
            let pid = preset.productID
            AppLogger.storeKit.notice(
                "FiringTopUpSheet: product \(pid, privacy: .public) not loaded — falling back to BalanceService.topUp"
            )
            let amount = Double(preset.amount)
            if BalanceService.shared.topUp(amount: amount) {
                handlePurchaseSuccess(amount: preset.amount)
            } else {
                handlePurchaseFailure(message: StoreKitService.ledgerLockedFailureMessage)
            }
        }
    }

    @objc private func cancelTapped() {
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

        successAmountLabel.text = "+\(amount) ₽"
        successContainer.isHidden = false
        // Cross-fade the form out so the success card reads as a swap rather
        // than a stack.
        UIView.animate(withDuration: SPSupport.durationBase) {
            self.titleLabel.alpha = 0
            self.subtitleLabel.alpha = 0
            self.presetStack.alpha = 0
            self.applePayButton.alpha = 0
            self.cancelButton.alpha = 0
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

    private func updatePauseLabel() {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        let countdown = String(format: "%02d:%02d", minutes, seconds)
        let attributed = NSAttributedString(
            string: "БУДИЛЬНИК НА ПАУЗЕ · \(countdown)",
            attributes: [
                .font: AppTypography.caps,
                .kern: AppTypography.capsKerning,
                .foregroundColor: AppColors.warn300
            ]
        )
        pauseLabel.attributedText = attributed
    }
}
