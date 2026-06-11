import UIKit
import StoreKit

/// State / notifications / data-refresh helpers for `TopUpViewController`.
/// Pulled out of the controller so the host file stays focused on init
/// + lifecycle + actions.
extension TopUpViewController {

    // MARK: - Notifications

    func wireStoreCallbacks() {
        let center = NotificationCenter.default

        // Capture user-info keys outside the closure so the closure
        // body doesn't read main-actor-isolated statics at delivery
        // time (matches the FiringTopUpBottomSheetViewController pattern).
        let amountKey = StoreKitService.amountUserInfoKey
        let messageKey = StoreKitService.messageUserInfoKey

        purchaseFailedObserver = center.addObserver(
            forName: StoreKitService.purchaseFailedNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let message = note.userInfo?[messageKey] as? String
                ?? "Покупка не выполнена. Попробуйте ещё раз."
            self.handlePurchaseFailure(message: message)
        }

        purchasePendingObserver = center.addObserver(
            forName: StoreKitService.purchasePendingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.presentPendingAlert()
        }

        purchaseCompletedObserver = center.addObserver(
            forName: StoreKitService.purchaseCompletedNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let amount = note.userInfo?[amountKey] as? Double ?? Double(self.selectedAmount)
            self.handlePurchaseSuccess(amount: Int(amount.rounded()))
        }

        balanceChangedObserver = center.addObserver(
            forName: BalanceService.balanceChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshBalanceCard()
        }
    }

    // MARK: - Balance card refresh

    /// Re-read the wallet balance + week delta and push them into the
    /// SPBalanceCard. The week delta is the sum of `charge` transactions
    /// from the last 7 days; rendered as a negative arrow because
    /// charges removed money from the wallet.
    func refreshBalanceCard() {
        let balance = Decimal(balanceService.balance)
        let weekDelta = computeWeekDelta()
        balanceCard.update(balance: balance, delta: weekDelta, hint: nil)
    }

    /// Sum of `charge`-type transactions in the last 7 days, returned as
    /// a negative `Decimal` so the SPBalanceCard renders with the down
    /// arrow + pain tint. `nil` if the window is empty (delta row hidden).
    func computeWeekDelta() -> Decimal? {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let charges = transactionRepository.fetchCharges(since: weekAgo)
        guard !charges.isEmpty else { return nil }
        let total = charges.reduce(0.0) { $0 + $1.amount }
        guard total > 0 else { return nil }
        // Negative sign: charges removed money during the week.
        return -Decimal(total)
    }

    // MARK: - Loading

    func loadStoreProducts() {
        Task { [weak self] in
            await self?.storeService.loadProducts()
            await MainActor.run {
                guard let self else { return }
                self.didFinishInitialLoad = true
                self.applePayButton.isEnabled = !self.purchaseInFlight
            }
        }
    }

    // MARK: - Success / failure

    /// Cross-fade the form into the success overlay and auto-dismiss
    /// the sheet 2 seconds later so the user lands back on the alarms
    /// list without an extra tap.
    func handlePurchaseSuccess(amount: Int) {
        guard successAmount == nil else { return }
        successAmount = amount
        purchaseInFlight = false

        successAmountLabel.text = "+\(MoneyFormatter.string(amount))"
        successContainer.isHidden = false

        UIView.animate(withDuration: SPSupport.durationBase) {
            self.contentStack.alpha = 0
            self.successContainer.alpha = 1
        }

        // Refresh the balance card behind the overlay so when the user
        // opens the wallet again the new balance is already there
        // (BalanceService has already topped up at this point).
        refreshBalanceCard()

        // Re-rasterise the gradient mask once the new "+N ₽" text has
        // measured itself.
        view.setNeedsLayout()
        view.layoutIfNeeded()
        applySuccessGradient()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.dismiss(animated: true)
        }
    }

    func handlePurchaseFailure(message: String) {
        purchaseInFlight = false
        applePayButton.isEnabled = didFinishInitialLoad
        presentErrorAlert(message)
    }

    // MARK: - Alerts

    func presentErrorAlert(_ message: String) {
        let alert = UIAlertController(title: "Ошибка", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    func presentPendingAlert() {
        let alert = UIAlertController(
            title: "Ожидаем подтверждения",
            message: "Покупка ожидает одобрения родителя. Баланс пополнится автоматически.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
