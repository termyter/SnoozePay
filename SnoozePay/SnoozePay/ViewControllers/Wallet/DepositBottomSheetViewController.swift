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

    // MARK: - Subviews

    private let dragHandle: UIView = {
        let view = UIView()
        view.backgroundColor = AppColors.whiteOverlay12
        view.layer.cornerRadius = 2
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
        view.layer.cornerRadius = 40
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
                ) { _ in 430 }
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
        contentStack.setCustomSpacing(AppSpacing.sp5, after: titleLabel)
        contentStack.setCustomSpacing(AppSpacing.sp5, after: grid)
        contentStack.setCustomSpacing(AppSpacing.sp3, after: ctaHost)

        successContainer.addSubview(successCheck)
        successContainer.addSubview(successAmountLabel)
        successContainer.addSubview(successCaption)

        let inset = AppSpacing.screenInset
        NSLayoutConstraint.activate([
            dragHandle.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            dragHandle.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            dragHandle.widthAnchor.constraint(equalToConstant: 36),
            dragHandle.heightAnchor.constraint(equalToConstant: 4),

            contentStack.topAnchor.constraint(equalTo: dragHandle.bottomAnchor, constant: AppSpacing.sp4),
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: inset),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -inset),

            successContainer.topAnchor.constraint(equalTo: view.topAnchor),
            successContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            successContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            successContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            successCheck.centerXAnchor.constraint(equalTo: successContainer.centerXAnchor),
            successCheck.centerYAnchor.constraint(equalTo: successContainer.centerYAnchor, constant: -52),
            successCheck.widthAnchor.constraint(equalToConstant: 80),
            successCheck.heightAnchor.constraint(equalToConstant: 80),

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
        guard let preset = DepositPresets.preset(forAmount: selectedAmount) else { return }
        purchaseInFlight = true
        depositButton.isEnabled = false

        if let product = StoreKitService.shared.products.first(where: { $0.id == preset.productID }) {
            Task { @MainActor in
                await StoreKitService.shared.purchase(product)
            }
        } else {
            let pid = preset.productID
            AppLogger.storeKit.notice(
                "DepositSheet: product \(pid, privacy: .public) not loaded — falling back to BalanceService.topUp"
            )
            if BalanceService.shared.topUp(amount: Double(preset.amount)) {
                handlePurchaseSuccess(amount: preset.amount)
            } else {
                handlePurchaseFailure(message: StoreKitService.ledgerLockedFailureMessage)
            }
        }
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
