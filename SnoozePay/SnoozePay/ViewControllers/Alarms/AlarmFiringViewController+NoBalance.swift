import StoreKit
import UIKit
import os

/// No-balance («Баланса не осталось») state for the firing screen — V2 spec.
///
/// V2 (`SPScreensV2.jsx` lines 228–276, `FiringNoBalanceV2`):
/// - Background tone flips to "drained" (handled by the host VC's
///   `updateAtmosphereTone`).
/// - Top-right balance pill switches to pain (also host-handled).
/// - Center adds a pain-tinted shield pill «БАЛАНСА НЕ ОСТАЛОСЬ» plus the
///   body «Откладывать больше не получится. Только встать.» (lines 239–251).
/// - Bottom CTAs:
///   1. Disabled `SPSnoozePrice` (hint «Недостаточно средств») — visual
///      continuity so the user sees what they wanted to tap.
///   2. `SPButton(.money, .lg, fullWidth)` "Apple Pay · N ₽" (N = catalogue
///      amount of the resolved SKU) — single-tap purchase via StoreKitService.
///   3. `SPButton(.ghost, .lg, fullWidth)` «Я встал — выключить».
///
/// Auto-recovery: `BalanceService.balanceChangedNotification` triggers a
/// `refreshNoBalanceVisibility()` flip back to the normal Dawn snooze CTA
/// once the user crosses the affordability threshold.
extension AlarmFiringViewController {

    /// SKU resolved by the no-balance Apple Pay tap. Targets the 499 ₽ tier;
    /// the 500 ₽ SKU doesn't exist in App Store Connect (lineup is PM's #240).
    static var noBalanceProductID: String { "io.mobilife.snoozepay.balance.499" }

    /// Display amount (₽) for the no-balance Apple Pay button title. Derived
    /// from the catalogue amount of `noBalanceProductID` so the rendered number
    /// equals what the App Store charges and the ledger credits — see #275. The
    /// CTA used to show 500 ₽ over the 499 SKU (display != charge != credit).
    static var noBalanceDisplayAmount: Int {
        StoreKitService.catalogAmount(for: noBalanceProductID) ?? 0
    }

    // MARK: - Setup

    /// Build the no-balance stack and the center «Баланса не осталось» block.
    /// All views start hidden; `refreshNoBalanceVisibility()` toggles them
    /// based on `viewModel.canSnooze`.
    func installNoBalanceStack(inset: CGFloat, gap: CGFloat) {
        // Center pain pill + body — slots into the centre column under the
        // hero when the no-balance state is on.
        installNoBalanceCenterPill(inset: inset)
        // Room for the column to come from: the hero's slide-up slack (#547).
        installNoBalanceColumnSlack()

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
        // 12pt gap between primary stack items, tightened to 8pt before the
        // quiet "choose amount" link so the link reads as subordinate to the
        // ghost dismiss CTA.
        stack.spacing = gap
        stack.setCustomSpacing(AppSpacing.sp2, after: ghostDismiss)
        stack.alignment = .fill
        stack.isHidden = true   // toggled by `refreshNoBalanceVisibility`
        view.addSubview(stack)
        noBalanceContainer = stack

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: inset),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -inset),
            stack.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -AppSpacing.sp7   // 32pt bottom inset per V2 spec
            )
        ])

        // Keep the center «Баланса не осталось» block off the disabled price
        // card at the top of this stack (#345). Required — and since #547 it is
        // no longer the only required constraint on the block: there is a floor
        // under it too, so the pair can't be satisfied by printing over the
        // hero. Activated with the state (`setNoBalanceColumnActive`), because
        // while the wallet is solvent the block is hidden and its idle pin is
        // all it needs.
        if let centerBlock = noBalanceCenterBlock {
            noBalanceColumn.blockBottom = centerBlock.bottomAnchor.constraint(
                lessThanOrEqualTo: stack.topAnchor, constant: -AppSpacing.sp4
            )
        }
    }

    private func makeNoBalanceDisabledCard() -> SPSnoozePrice {
        let card = SPSnoozePrice(
            price: Decimal(viewModel.currentPenalty),
            minutes: viewModel.alarm.snoozeMinutes,
            tone: .warn,
            hint: Localized.text("firing.no_balance.hint")
        )
        card.translatesAutoresizingMaskIntoConstraints = false
        card.isEnabled = false
        // Spec calls for an extra-faded surface (alpha 0.5 vs the
        // `SPSnoozePrice` default 0.35) — the .35 reads as "tap me" still,
        // .5 reads as "this is the goal you can't hit yet" (#227). Override the
        // disabled appearance after the fact since it's set in the setter.
        card.alpha = 0.5
        return card
    }

    private func makeNoBalanceApplePayButton() -> SPButton {
        // V3 (#227): neutral green money CTA — wallet icon + «Пополнить» + the
        // amount suffix. NO "Apple Pay ·" in the label (cross-platform neutral
        // copy, PM decision chat2); the purchase still runs through StoreKit /
        // Apple Pay under the hood — only the visible branding is dropped, so
        // the `applePay*` identifiers stay accurate. Suffix keeps the catalogue
        // amount of the resolved SKU (#275: display == charge == credit) rather
        // than a hardcoded 500 ₽, so the rendered number matches what's charged.
        let button = SPButton(
            title: Localized.text("common.button.top_up"),
            variant: .money,
            size: .lg,
            icon: SPIcons.wallet(size: 20),
            suffix: MoneyFormatter.string(Self.noBalanceDisplayAmount),
            fullWidth: true
        )
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityIdentifier = "firing.noBalance.topUpButton"
        button.addTarget(
            self,
            action: #selector(noBalanceApplePayTapped),
            for: .touchUpInside
        )
        return button
    }

    private func makeNoBalanceGhostDismissButton() -> SPButton {
        let button = SPButton(
            title: Localized.text("firing.button.dismiss"),
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
            title: Localized.text("firing.no_balance.choose_amount"),
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
        // #398: while the snoozed countdown owns the screen, never surface the
        // no-balance stack — even if a mid-snooze balance notification re-runs
        // this pass with `canSnooze == false`. `exitSnoozedState` re-calls this
        // after clearing the flag, so the stack returns correctly on teardown.
        let showNoBalanceStack = needsNoBalance && !isSnoozedStateActive
        // Refresh the disabled card's hint + price each pass so progressive
        // alarms show the correct disabled value even after snoozeCount has
        // bumped the next penalty.
        if let card = noBalanceSnoozeCard {
            card.update(
                price: Decimal(viewModel.currentPenalty),
                minutes: viewModel.alarm.snoozeMinutes,
                hint: Localized.text("firing.no_balance.hint")
            )
        }
        noBalanceContainer?.isHidden = !showNoBalanceStack
        noBalanceCenterBlock?.isHidden = !showNoBalanceStack
        // The centre column's geometry follows the block it holds: three zones
        // sharing the height while the warning is up, the shipped hero pin the
        // rest of the time (#547).
        setNoBalanceColumnActive(showNoBalanceStack)
        // Drained background + red glow + neutral clock + accent wake-border.
        applyDrainedAtmosphere(needsNoBalance)
        // Hide the normal-state group when the no-balance stack takes over.
        // The progressive chrome (centre-hero indicator pill + ticker) is also
        // hidden so it doesn't float over the no-balance layout.
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
        // by parent, ledger locked) as a UIAlert. Success is implicit — the
        // balanceChanged observer above handles UI recovery for that path.
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

    /// Apple Pay tap (catalogue amount of the resolved SKU). Resolves the
    /// StoreKit product if loaded,
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
            // Foreign storefront: refuse before `purchase(_:)`, while refusing
            // is still free (#563).
            if let blocked = ForeignCurrencyNotice.blockingMessage(for: product) {
                noBalancePurchaseInFlight = false
                applePayNoBalanceButton?.isEnabled = true
                present(ForeignCurrencyNotice.alert(message: blocked), animated: true)
                return
            }
            Task { @MainActor in
                await StoreKitService.shared.purchase(product)
            }
            return
        }

        // Product list hasn't loaded yet.
        #if DEBUG
        // DEBUG/simulator: credit locally so the flow stays testable.
        AppLogger.storeKit.notice(
            "noBalanceApplePayTapped: product \(productID, privacy: .public) not loaded — DEBUG fallback to topUp"
        )
        let amount = Double(Self.noBalanceDisplayAmount)
        if BalanceService.shared.topUp(amount: amount) {
            return
        }
        #else
        // Release: never credit without a real StoreKit transaction —
        // fall through to reset + the failure alert below.
        AppLogger.storeKit.error(
            "noBalanceApplePayTapped: product \(productID, privacy: .public) not loaded — purchase unavailable (no local credit in release)"
        )
        #endif
        noBalancePurchaseInFlight = false
        applePayNoBalanceButton?.isEnabled = true
        presentNoBalancePurchaseFailureAlert(
            message: StoreKitService.ledgerLockedFailureMessage
        )
    }

    /// «Выбрать другую сумму» tap. Routes to the presets bottom sheet.
    @objc func noBalanceChooseAmountTapped() {
        presentTopUpSheet()
    }

    // MARK: - Helpers

    private func presentNoBalancePurchaseFailureAlert(message: String?) {
        let alert = UIAlertController(
            title: Localized.text("firing.alert.purchase_failed.title"),
            message: message ?? Localized.text("firing.alert.purchase_failed.message"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: Localized.text("common.button.ok"), style: .default))
        present(alert, animated: true)
    }
}

// MARK: - Center block storage
//
// Extending the host VC with a stored property is illegal in Swift, so we
// route the «Баланса не осталось» center block through an associated-object
// keyed accessor. Single storage slot keyed by a unique pointer; reads /
// writes happen on the main thread only (firing screen is main-only).

private var noBalanceCenterBlockKey: UInt8 = 0

extension AlarmFiringViewController {
    /// Reference to the center «Баланса не осталось» pill + body stack. We
    /// store it via associated objects rather than a stored property because
    /// the main VC body is already on the SwiftLint type_body_length limit;
    /// adding another property would push it over and the file split has
    /// been the recurring fix for this VC.
    var noBalanceCenterBlock: UIStackView? {
        get {
            objc_getAssociatedObject(self, &noBalanceCenterBlockKey) as? UIStackView
        }
        set {
            objc_setAssociatedObject(
                self,
                &noBalanceCenterBlockKey,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }
}
