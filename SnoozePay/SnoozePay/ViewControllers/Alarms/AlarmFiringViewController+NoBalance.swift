import StoreKit
import UIKit
import os

/// No-balance ("Баланс закончился") state for the firing screen — issue #140,
/// closes the silent-failure UX from #26.
///
/// When `viewModel.canSnooze == false` the snooze CTA + dismiss group is
/// swapped for a four-row stack:
/// 1. Disabled `SPSnoozePrice` (warn tone, alpha 0.45) with the hint
///    "Баланса не хватает · нужно ≥ N ₽" — keeps the visual continuity so
///    the user sees what they were trying to do.
/// 2. `SPButton(.money, .lg, fullWidth)` "Apple Pay · 500 ₽" — single-tap
///    purchase via `StoreKitService.purchase` against SKU
///    `com.snooze_pay.balance.499`. Falls back to `BalanceService.topUp`
///    when the StoreKit product list hasn't loaded (debug / unit-test
///    paths) so the wallet still credits end-to-end. PM directive
///    (`Questions answered: no_balance_button`) was an explicit
///    "Apple Pay в один тап на дефолтную сумму (500 ₽), без выбора".
/// 3. `SPButton(.ghost, .lg, fullWidth)` "Я встал — выключить" — BIG
///    button per PM directive (chat1.md line 1180): "должна быть большой",
///    not a small text link. Reuses the host VC's `dismissTapped` so the
///    repeat-day disable + scheduler.cancel paths are identical.
/// 4. `SPButton(.quiet, .sm, fullWidth)` "Выбрать другую сумму" — opens
///    the bottom sheet from #141 for users who want a different amount.
///
/// Auto-recovery: `BalanceService.balanceChangedNotification` triggers a
/// `refreshNoBalanceVisibility()` flip back to the normal Dawn snooze CTA
/// once the user crosses the affordability threshold (purchase success,
/// external charge in another tab, manual debug top-up).
extension AlarmFiringViewController {

    /// SKU resolved by the no-balance Apple Pay tap. Hard-coded to the
    /// 499 ₽ tier rather than a 500 ₽ SKU because the latter doesn't yet
    /// exist in App Store Connect. PM follow-up tracked: register an exact
    /// `com.snooze_pay.balance.500` SKU and swap this constant when it's
    /// ready (mirrors the same caveat documented in
    /// `FiringTopUpBottomSheetViewController.Preset.productID`).
    static var noBalanceProductID: String { "com.snooze_pay.balance.499" }

    /// Display amount (₽) for the no-balance Apple Pay button title. Kept
    /// separate from the SKU because the SKU and the UI label diverge
    /// today (499 SKU surfaced as "500 ₽" copy per PM spec) and we don't
    /// want the title to drift if the SKU mapping changes.
    static var noBalanceDisplayAmount: Int { 500 }

    // MARK: - Setup

    /// Build the four-row no-balance stack and pin it to the bottom of the
    /// screen using the same insets / gap as the normal snooze CTA. The
    /// stack starts hidden — `refreshNoBalanceVisibility()` toggles it
    /// based on `viewModel.canSnooze`.
    func installNoBalanceStack(inset: CGFloat, gap: CGFloat) {
        let disabledCard = makeNoBalanceDisabledCard()
        let payButton = makeNoBalanceApplePayButton()
        let ghostDismiss = makeNoBalanceGhostDismissButton()
        let chooseLink = makeNoBalanceChooseAmountLink()

        noBalanceSnoozeCard = disabledCard
        applePayNoBalanceButton = payButton
        noBalanceDismissButton = ghostDismiss
        chooseAmountLink = chooseLink

        let stack = UIStackView(arrangedSubviews: [
            disabledCard, payButton, ghostDismiss, chooseLink
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        // Custom spacing per pair so the disabled card → Apple Pay gap
        // matches the spec's 12pt while the Apple Pay → ghost gap also
        // reads as 12pt and the ghost → quiet link tightens to 8pt
        // (the link is intentionally subordinate to the ghost CTA).
        stack.spacing = gap
        stack.setCustomSpacing(AppSpacing.sp2, after: ghostDismiss)
        stack.alignment = .fill
        stack.isHidden = true   // toggled by `refreshNoBalanceVisibility`
        view.addSubview(stack)
        noBalanceContainer = stack

        // Pin to the same bottom anchor as the normal-state dismissButton
        // so the stack lands in the same screen region. Leading/trailing
        // pinned to the same insets so the disabled card and Apple Pay
        // button visually inherit the snooze CTA's footprint.
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: inset),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -inset),
            stack.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -AppSpacing.sp6
            )
        ])
    }

    private func makeNoBalanceDisabledCard() -> SPSnoozePrice {
        let card = SPSnoozePrice(
            price: Decimal(viewModel.currentPenalty),
            minutes: viewModel.alarm.snoozeMinutes,
            tone: .warn,
            hint: noBalanceHintText()
        )
        card.translatesAutoresizingMaskIntoConstraints = false
        card.isEnabled = false
        // Spec calls for an extra-faded surface (alpha 0.45 vs the
        // `SPSnoozePrice` default 0.35) — the .35 reads as "tap me" still,
        // .45 reads as "this is the goal you can't hit yet". Override the
        // disabled appearance after the fact since it's set in the setter.
        card.alpha = 0.45
        return card
    }

    private func makeNoBalanceApplePayButton() -> SPButton {
        let button = SPButton(
            title: "Apple Pay · \(Self.noBalanceDisplayAmount) ₽",
            variant: .money,
            size: .lg,
            icon: UIImage(systemName: "applelogo"),
            fullWidth: true
        )
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(
            self,
            action: #selector(noBalanceApplePayTapped),
            for: .touchUpInside
        )
        return button
    }

    private func makeNoBalanceGhostDismissButton() -> SPButton {
        let button = SPButton(
            title: "Я встал — выключить",
            variant: .ghost,
            size: .lg,
            fullWidth: true
        )
        button.translatesAutoresizingMaskIntoConstraints = false
        // Reuse the host VC's dismiss handler so the repeat-day disable +
        // scheduler.cancel paths from `AlarmFiringViewModel.dismiss()` are
        // identical between normal and no-balance states.
        button.addTarget(
            self,
            action: #selector(dismissTapped),
            for: .touchUpInside
        )
        return button
    }

    private func makeNoBalanceChooseAmountLink() -> SPButton {
        let button = SPButton(
            title: "Выбрать другую сумму",
            variant: .quiet,
            size: .sm,
            fullWidth: true
        )
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(
            self,
            action: #selector(noBalanceChooseAmountTapped),
            for: .touchUpInside
        )
        return button
    }

    // MARK: - Visibility swap

    /// Toggle between the normal snooze + dismiss group and the no-balance
    /// stack based on `viewModel.canSnooze`. Called from `updateUI()` (so
    /// every VM state change rechecks) and from the balance observer (so
    /// external top-ups also flip the state).
    func refreshNoBalanceVisibility() {
        let needsNoBalance = !viewModel.canSnooze
        // Refresh the disabled card's hint + price each pass so progressive
        // alarms (#139) show the correct "нужно ≥ N ₽" amount even after
        // snoozeCount has bumped the next penalty.
        if let card = noBalanceSnoozeCard {
            card.update(
                price: Decimal(viewModel.currentPenalty),
                minutes: viewModel.alarm.snoozeMinutes,
                hint: noBalanceHintText()
            )
        }
        noBalanceContainer?.isHidden = !needsNoBalance
        // Hide the normal-state group when the no-balance stack takes over.
        // The progressive stack is also hidden (it sits above the snooze
        // CTA and would orphan above a hidden card otherwise).
        snoozeCTA?.isHidden = needsNoBalance
        dismissButton.isHidden = needsNoBalance
        progressiveStack?.isHidden = needsNoBalance || !viewModel.isProgressiveActive
    }

    // MARK: - Balance observation

    /// Subscribe to `BalanceService.balanceChangedNotification` so that
    /// the no-balance state flips back to the normal Dawn snooze CTA
    /// automatically once the user crosses the affordability threshold
    /// (purchase success, external charge, debug top-up).
    func observeBalanceForNoBalanceState() {
        balanceChangeObserver = NotificationCenter.default.addObserver(
            forName: BalanceService.balanceChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            // `updateUI` re-reads `viewModel.canSnooze` and re-runs
            // `refreshNoBalanceVisibility` so a single hop here covers
            // the whole swap (snooze CTA tone, disabled card hint, etc).
            self.updateUI()
            self.noBalancePurchaseInFlight = false
            self.applePayNoBalanceButton?.isEnabled = true
        }
        // Surface StoreKit failures (Ask-to-Buy declined, purchase cancelled
        // by parent, ledger locked) as a UIAlert so the user knows the tap
        // didn't actually credit. Success is implicit — the balanceChanged
        // observer above handles UI recovery for that path.
        let messageKey = StoreKitService.messageUserInfoKey
        purchaseFailedObserver = NotificationCenter.default.addObserver(
            forName: StoreKitService.purchaseFailedNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            self.noBalancePurchaseInFlight = false
            self.applePayNoBalanceButton?.isEnabled = true
            let message = note.userInfo?[messageKey] as? String
            self.presentNoBalancePurchaseFailureAlert(message: message)
        }
    }

    // MARK: - Actions

    /// Apple Pay 500 ₽ tap. Resolves the StoreKit product if loaded,
    /// otherwise falls back to a direct `BalanceService.topUp` so the
    /// debug / test paths still credit. The re-entrancy guard
    /// (`noBalancePurchaseInFlight`) and `isEnabled = false` flip together
    /// so a double-tap doesn't kick off two purchases.
    @objc func noBalanceApplePayTapped() {
        guard !noBalancePurchaseInFlight else { return }
        noBalancePurchaseInFlight = true
        applePayNoBalanceButton?.isEnabled = false

        let productID = Self.noBalanceProductID
        if let product = StoreKitService.shared.products.first(where: { $0.id == productID }) {
            Task { @MainActor in
                await StoreKitService.shared.purchase(product)
            }
            return
        }

        // Product list hasn't loaded yet — fall back to a direct top-up so
        // we still recover the user's flow. The fallback amount mirrors
        // the displayed copy (500 ₽), not the underlying SKU price (499 ₽),
        // because that's what the user agreed to in the button label.
        AppLogger.storeKit.notice(
            "noBalanceApplePayTapped: product \(productID, privacy: .public) not loaded — fallback to topUp"
        )
        let amount = Double(Self.noBalanceDisplayAmount)
        if BalanceService.shared.topUp(amount: amount) {
            // BalanceService posts `balanceChangedNotification` synchronously
            // here, which trips the observer and resets in-flight state.
            return
        }
        // Ledger locked / corrupt — surface the same copy StoreKitService
        // would post so the user gets a consistent error message.
        noBalancePurchaseInFlight = false
        applePayNoBalanceButton?.isEnabled = true
        presentNoBalancePurchaseFailureAlert(
            message: StoreKitService.ledgerLockedFailureMessage
        )
    }

    /// "Выбрать другую сумму" tap. Routes to the existing #141 bottom
    /// sheet so the rich preset / Apple Pay flow handles the choice.
    @objc func noBalanceChooseAmountTapped() {
        presentTopUpSheet()
    }

    // MARK: - Helpers

    /// Hint copy for the disabled snooze card. Uses the current penalty so
    /// progressive alarms surface the doubled amount they actually need.
    private func noBalanceHintText() -> String {
        let needed = Int(viewModel.currentPenalty.rounded())
        return "Баланса не хватает · нужно ≥ \(needed) ₽"
    }

    private func presentNoBalancePurchaseFailureAlert(message: String?) {
        let alert = UIAlertController(
            title: "Покупка не выполнена",
            message: message ?? "Попробуйте ещё раз.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Ок", style: .default))
        present(alert, animated: true)
    }
}
