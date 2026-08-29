import StoreKit
import UIKit
import os

/// Deposit bottom sheet — V3 design `Deposit` in
/// `docs/design/v2-handoff/components/SPMore3.jsx` (artboard 19, issue #233).
///
/// Presented over the live (dimmed) Wallet tab via a page-sheet with a
/// custom detent, so the underlying screen stays visible behind the scrim.
/// Layout, top-down: drag handle → "Пополнить баланс" (h2) → 3-column
/// preset grid (live StoreKit SKUs from `DepositPresets`) → money CTA
/// "Пополнить" with wallet icon + selected-amount suffix → disclaimer.
///
/// Purchase flow mirrors `FiringTopUpBottomSheetViewController`: tap →
/// `StoreKitService.purchase(_:)`; success / failure arrive via the
/// service's notifications. When the product list hasn't loaded (debug /
/// simulator without StoreKit config) the sheet falls back to a direct
/// `BalanceService.topUp` credit so the flow stays demoable.
///
/// On success the form crossfades into a green check + "+N ₽" state and
/// auto-dismisses after 2 seconds.
final class DepositBottomSheetViewController: UIViewController {

    // MARK: - Metrics
    //
    // `SPMore3.jsx` L430 renders the drag handle as a 36x4 pill; the success
    // check is an 80pt circle. Both radii are derived from their own size so
    // a metric bump can't leave a stale corner behind.
    private static let dragHandleSize = CGSize(width: 36, height: 4)
    private static let successCheckDiameter: CGFloat = 80

    // MARK: - State

    private let presets = DepositPresets.presets
    private var selectedAmount: Int = DepositPresets.defaultAmount

    /// Suppresses re-taps while StoreKit is busy with the first one.
    private var purchaseInFlight = false

    /// Set once a successful purchase resolves — guards double-delivery
    /// (foreground purchase + background `Transaction.updates` listener).
    private var successAmount: Int?

    private var purchaseCompletedObserver: NSObjectProtocol?
    private var purchaseFailedObserver: NSObjectProtocol?
    /// True while this screen is registered as a purchase-feedback subscriber
    /// so `begin`/`end` stay balanced across appear/disappear (#45).
    private var isObservingPurchaseFeedback = false

    // MARK: - Subviews

    private let dragHandle: UIView = {
        let view = UIView()
        view.backgroundColor = AppColors.whiteOverlay12
        view.layer.cornerRadius = DepositBottomSheetViewController.dragHandleSize.height / 2
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.attributedText = NSAttributedString(
            string: "Пополнить баланс",
            attributes: [
                .font: AppTypography.h2,
                .kern: -24 * 0.01,
                .foregroundColor: AppColors.fg1
            ]
        )
        return label
    }()

    private var presetTiles: [SPAmountPreset] = []

    private let contentStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = AppSpacing.sp4
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    /// Single-child host for the CTA — `SPButton` title/suffix is immutable
    /// post-init, so selection changes swap the arranged subview and the
    /// stack re-pins the replacement automatically.
    private let ctaHost: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        return stack
    }()

    private lazy var depositButton: SPButton = makeDepositButton(amount: selectedAmount)

    private let disclaimerLabel: UILabel = {
        let label = UILabel()
        label.font = AppTypography.meta
        label.textColor = AppColors.fg3
        label.textAlignment = .center
        label.numberOfLines = 0
        label.text = "Деньги попадают в баланс. Списываются только при откладывании."
        return label
    }()

    /// App Store-required restore affordance, folded in from the retired
    /// `TopUpViewController` (#281) so this single Deposit surface keeps it.
    private lazy var restoreButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.attributedTitle = AttributedString(
            "Восстановить покупки",
            attributes: AttributeContainer([
                .font: AppTypography.meta,
                .foregroundColor: AppColors.fg2
            ])
        )
        let button = UIButton(configuration: config)
        button.addTarget(self, action: #selector(restoreTapped), for: .touchUpInside)
        return button
    }()

    // MARK: - Success overlay

    private let successContainer: UIView = {
        let view = UIView()
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let successCheck: UIImageView = {
        let configuration = UIImage.SymbolConfiguration(pointSize: 40, weight: .bold)
        let image = UIImage(systemName: "checkmark", withConfiguration: configuration)
        let view = UIImageView(image: image)
        view.tintColor = AppColors.fgOnMoney
        view.contentMode = .center
        view.backgroundColor = AppColors.money500
        view.layer.cornerRadius = DepositBottomSheetViewController.successCheckDiameter / 2
        view.layer.masksToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let successAmountLabel: UILabel = {
        let label = UILabel()
        label.font = AppTypography.moneyLg
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
        label.text = "Зачислено на баланс"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - Init

    init() {
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        if let sheet = sheetPresentationController {
            if #available(iOS 16.0, *) {
                let custom = UISheetPresentationController.Detent.custom(
                    identifier: UISheetPresentationController.Detent.Identifier("snoozepay.deposit")
                ) { _ in 474 }
                sheet.detents = [custom, .large()]
            } else {
                sheet.detents = [.medium(), .large()]
            }
            sheet.prefersGrabberVisible = false  // we render our own handle
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
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColors.bg1
        setupLayout()
        observePurchaseNotifications()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // While this screen is visible, purchase feedback routes to the in-app
        // banner; tell StoreKitService so it doesn't also post a fallback local
        // notification (#45). Balanced in `viewWillDisappear`.
        if !isObservingPurchaseFeedback {
            isObservingPurchaseFeedback = true
            StoreKitService.shared.beginObservingPurchaseFeedback()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isObservingPurchaseFeedback {
            isObservingPurchaseFeedback = false
            StoreKitService.shared.endObservingPurchaseFeedback()
        }
    }

    // MARK: - Layout

    private func setupLayout() {
        view.addSubview(dragHandle)
        view.addSubview(contentStack)
        view.addSubview(successContainer)

        let grid = makePresetGrid()
        contentStack.addArrangedSubview(titleLabel)
        contentStack.addArrangedSubview(grid)
        ctaHost.addArrangedSubview(depositButton)
        contentStack.addArrangedSubview(ctaHost)
        contentStack.addArrangedSubview(disclaimerLabel)
        contentStack.addArrangedSubview(restoreButton)
        contentStack.setCustomSpacing(AppSpacing.sp5, after: titleLabel)
        contentStack.setCustomSpacing(AppSpacing.sp5, after: grid)
        contentStack.setCustomSpacing(AppSpacing.sp3, after: ctaHost)
        contentStack.setCustomSpacing(AppSpacing.sp2, after: disclaimerLabel)

        successContainer.addSubview(successCheck)
        successContainer.addSubview(successAmountLabel)
        successContainer.addSubview(successCaption)

        let inset = AppSpacing.screenInset
        NSLayoutConstraint.activate([
            dragHandle.topAnchor.constraint(equalTo: view.topAnchor, constant: AppSpacing.sp2),
            dragHandle.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            dragHandle.widthAnchor.constraint(equalToConstant: Self.dragHandleSize.width),
            dragHandle.heightAnchor.constraint(equalToConstant: Self.dragHandleSize.height),

            contentStack.topAnchor.constraint(equalTo: dragHandle.bottomAnchor, constant: AppSpacing.sp4),
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: inset),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -inset),

            successContainer.topAnchor.constraint(equalTo: view.topAnchor),
            successContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            successContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            successContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            successCheck.centerXAnchor.constraint(equalTo: successContainer.centerXAnchor),
            successCheck.centerYAnchor.constraint(equalTo: successContainer.centerYAnchor, constant: -52),
            successCheck.widthAnchor.constraint(equalToConstant: Self.successCheckDiameter),
            successCheck.heightAnchor.constraint(equalToConstant: Self.successCheckDiameter),

            successAmountLabel.topAnchor.constraint(equalTo: successCheck.bottomAnchor, constant: AppSpacing.sp4),
            successAmountLabel.leadingAnchor.constraint(equalTo: successContainer.leadingAnchor, constant: inset),
            successAmountLabel.trailingAnchor.constraint(equalTo: successContainer.trailingAnchor, constant: -inset),

            successCaption.topAnchor.constraint(equalTo: successAmountLabel.bottomAnchor, constant: AppSpacing.sp2),
            successCaption.leadingAnchor.constraint(equalTo: successContainer.leadingAnchor, constant: inset),
            successCaption.trailingAnchor.constraint(equalTo: successContainer.trailingAnchor, constant: -inset)
        ])
    }

    /// 3-column grid of `SPAmountPreset` tiles. The last row is padded with
    /// invisible spacers so a 5-SKU catalogue keeps uniform tile widths.
    private func makePresetGrid() -> UIView {
        let columns = 3
        var rows: [UIStackView] = []
        for rowStart in stride(from: 0, to: presets.count, by: columns) {
            let row = UIStackView()
            row.axis = .horizontal
            row.distribution = .fillEqually
            row.spacing = AppSpacing.sp2
            for index in rowStart..<min(rowStart + columns, presets.count) {
                let preset = presets[index]
                let tile = SPAmountPreset(
                    value: Decimal(preset.amount),
                    label: preset.label,
                    selected: preset.amount == selectedAmount,
                    popular: preset.popular
                ) { [weak self] in
                    self?.selectAmount(preset.amount)
                }
                presetTiles.append(tile)
                row.addArrangedSubview(tile)
            }
            while row.arrangedSubviews.count < columns {
                row.addArrangedSubview(UIView())
            }
            rows.append(row)
        }
        let grid = UIStackView(arrangedSubviews: rows)
        grid.axis = .vertical
        grid.spacing = AppSpacing.sp2
        return grid
    }

    private func makeDepositButton(amount: Int) -> SPButton {
        let button = SPButton(
            title: "Пополнить",
            variant: .money,
            size: .lg,
            icon: UIImage(systemName: "wallet.pass"),
            suffix: Decimal(amount).formattedRubles(),
            fullWidth: true
        )
        button.addTarget(self, action: #selector(depositTapped), for: .touchUpInside)
        return button
    }

    // MARK: - Selection

    private func selectAmount(_ amount: Int) {
        guard amount != selectedAmount else { return }
        selectedAmount = amount
        for (tile, preset) in zip(presetTiles, presets) {
            tile.isSelected = preset.amount == amount
        }
        // SPButton title/suffix is immutable post-init — swap the instance.
        depositButton.removeFromSuperview()
        depositButton = makeDepositButton(amount: amount)
        ctaHost.addArrangedSubview(depositButton)
    }

    // MARK: - Purchase

    private func observePurchaseNotifications() {
        let center = NotificationCenter.default
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

    @objc private func depositTapped() {
        guard !purchaseInFlight else { return }
        // Detect a corrupt balance BEFORE attempting a top-up (#419). The
        // BalanceService mutation gate stays locked until the user resets via
        // `acknowledgeCorruption()`, so a top-up here would always fail back
        // into the generic "Покупка не выполнена" retry loop the user can't
        // satisfy. Surface a corruption-specific message instead.
        guard !BalanceService.shared.balanceCorrupted else {
            presentBalanceCorruptionAlert()
            return
        }
        guard let preset = DepositPresets.preset(forAmount: selectedAmount) else { return }
        purchaseInFlight = true
        depositButton.isEnabled = false

        if let product = StoreKitService.shared.products.first(where: { $0.id == preset.productID }) {
            // Foreign storefront: refuse before `purchase(_:)`, while refusing
            // is still free (#563).
            if let blocked = ForeignCurrencyNotice.blockingMessage(for: product) {
                purchaseInFlight = false
                depositButton.isEnabled = true
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
                "DepositSheet: product \(pid, privacy: .public) not loaded — DEBUG fallback to BalanceService.topUp"
            )
            if BalanceService.shared.topUp(amount: Double(preset.amount)) {
                handlePurchaseSuccess(amount: preset.amount)
            } else {
                handlePurchaseFailure(message: StoreKitService.ledgerLockedFailureMessage)
            }
            #else
            // Release: NEVER credit balance without a real StoreKit
            // transaction. An empty product list (inactive Paid Apps /
            // unpropagated SKU / offline) must surface as an error, not as
            // free balance.
            AppLogger.storeKit.error(
                "DepositSheet: product \(pid, privacy: .public) not loaded — purchase unavailable (no local credit in release)"
            )
            handlePurchaseFailure(message: "Не удалось загрузить пакеты пополнения. Попробуйте позже.")
            #endif
        }
    }

    @objc private func restoreTapped() {
        performStoreKitRestore { [weak self] in
            self?.refreshBalanceAfterRestore()
        }
    }

    /// `Transaction.updates` inside `StoreKitService` credits the balance; this
    /// sheet only shows its own success state, so there's nothing to redraw
    /// here beyond logging. Kept as a hook so the closure reads intentionally.
    private func refreshBalanceAfterRestore() {
        AppLogger.storeKit.notice("DepositSheet: restore sync completed")
    }

    // MARK: - Success / failure

    private func handlePurchaseSuccess(amount: Int) {
        guard successAmount == nil else { return }
        successAmount = amount
        purchaseInFlight = false

        successAmountLabel.text = "+\(Decimal(amount).formattedRubles())"
        successContainer.isHidden = false
        successContainer.alpha = 0
        UIView.animate(withDuration: SPSupport.durationBase) {
            self.contentStack.alpha = 0
            self.successContainer.alpha = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.dismiss(animated: true)
        }
    }

    /// Corruption-specific alert shown when the user taps "Пополнить" while
    /// the stored balance is corrupt (#419). Unlike the generic purchase
    /// failure, this routes the user to reset the balance — the top-up gate
    /// stays locked until `acknowledgeCorruption()` runs, so retrying the
    /// purchase as the generic copy suggests can never succeed.
    private func presentBalanceCorruptionAlert() {
        let alert = UIAlertController(
            title: "Баланс повреждён",
            message: "Сохранённый баланс некорректен. Пополнение недоступно, "
                + "пока вы не сбросите баланс в ноль.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Сбросить", style: .destructive) { _ in
            BalanceService.shared.acknowledgeCorruption()
        })
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        present(alert, animated: true)
    }

    private func handlePurchaseFailure(message: String?) {
        purchaseInFlight = false
        depositButton.isEnabled = true

        let alert = UIAlertController(
            title: "Покупка не выполнена",
            message: message ?? "Попробуйте ещё раз.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Ок", style: .default))
        present(alert, animated: true)
    }
}
