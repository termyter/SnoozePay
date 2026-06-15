import StoreKit
import UIKit
import os

/// No-balance ("Баланса не осталось") state for the firing screen — V2 spec.
///
/// V2 (`SPScreensV2.jsx` lines 228–276, `FiringNoBalanceV2`):
/// - Background tone flips to "drained" (handled by the host VC's
///   `updateAtmosphereTone`).
/// - Top-right balance pill switches to pain (also host-handled).
/// - Center adds a pain-tinted shield pill "БАЛАНСА НЕ ОСТАЛОСЬ" plus the
///   body "Откладывать больше не получится. Только встать." (lines 239–251).
/// - Bottom CTAs:
///   1. Disabled `SPSnoozePrice` (hint "Недостаточно средств") — visual
///      continuity so the user sees what they wanted to tap.
///   2. `SPButton(.money, .lg, fullWidth)` "Apple Pay · N ₽" (N = catalogue
///      amount of the resolved SKU) — single-tap purchase via StoreKitService.
///   3. `SPButton(.ghost, .lg, fullWidth)` "Я встал — выключить".
///
/// Auto-recovery: `BalanceService.balanceChangedNotification` triggers a
/// `refreshNoBalanceVisibility()` flip back to the normal Dawn snooze CTA
/// once the user crosses the affordability threshold.
extension AlarmFiringViewController {

    /// SKU resolved by the no-balance Apple Pay tap. Targets the 499 ₽ tier;
    /// the 500 ₽ SKU doesn't exist in App Store Connect (lineup is PM's #240).
    static var noBalanceProductID: String { "com.snooze_pay.balance.499" }

    /// Display amount (₽) for the no-balance Apple Pay button title. Derived
    /// from the catalogue amount of `noBalanceProductID` so the rendered number
    /// equals what the App Store charges and the ledger credits — see #275. The
    /// CTA used to show 500 ₽ over the 499 SKU (display != charge != credit).
    static var noBalanceDisplayAmount: Int {
        StoreKitService.catalogAmount(for: noBalanceProductID) ?? 0
    }

    // MARK: - Setup

    /// Build the no-balance stack and the center "Баланса не осталось" block.
    /// All views start hidden; `refreshNoBalanceVisibility()` toggles them
    /// based on `viewModel.canSnooze`.
    func installNoBalanceStack(inset: CGFloat, gap: CGFloat) {
        // Center pain pill + body — anchored to the hero name label so it
        // tucks under the clock when the no-balance state is on.
        installNoBalanceCenterPill(inset: inset)

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

        // Keep the center "Баланса не осталось" block from colliding with the
        // disabled price card at the top of this stack (#345). Required, so it
        // wins over the block's breakable hero pin when the column is tight.
        if let centerBlock = noBalanceCenterBlock {
            centerBlock.bottomAnchor.constraint(
                lessThanOrEqualTo: stack.topAnchor, constant: -AppSpacing.sp4
            ).isActive = true
        }
    }

    /// Build the center "БАЛАНСА НЕ ОСТАЛОСЬ" pill + body text. Pinned below
    /// the hero name label so it slots into the centered column when the
    /// no-balance state activates. Mirrors `SPScreensV2.jsx` lines 239–251.
    private func installNoBalanceCenterPill(inset: CGFloat) {
        // Pain-tinted "coin off" pill — V3 swaps the shield glyph for the
        // crossed-out-coin icon used across the zero-balance surfaces (#227).
        let shieldPill = SPPill(
            text: "Баланса не осталось",
            tone: .pain,
            icon: SPIcons.coinOff(size: 14)
        )
        shieldPill.translatesAutoresizingMaskIntoConstraints = false

        let body = UILabel()
        body.translatesAutoresizingMaskIntoConstraints = false
        body.font = AppTypography.bodyLg
        body.textColor = UIColor.white.withAlphaComponent(0.7)
        body.textAlignment = .center
        body.numberOfLines = 0
        body.text = "Откладывать больше не получится. Только встать."

        let block = UIStackView(arrangedSubviews: [shieldPill, body])
        block.translatesAutoresizingMaskIntoConstraints = false
        block.axis = .vertical
        block.alignment = .center
        block.spacing = AppSpacing.sp4
        block.isHidden = true
        view.addSubview(block)
        noBalanceCenterBlock = block

        // Tuck under the eyebrow caps — V3 moved the name label above the
        // clock (#225), so the eyebrow is now the hero's bottom edge. This pin
        // is breakable (.defaultHigh) so the required "stay above the bottom
        // stack" constraint in `installNoBalanceStack` can win on a tight
        // column: the no-balance bottom stack is taller than the normal one
        // (disabled card + Apple Pay + dismiss + choose-amount, vs snooze +
        // dismiss), and without that safety net the body text overlaps the
        // disabled price card (#345). On the regular screen height there's
        // ample room, so this pin holds and the block stays tucked.
        let heroPin = block.topAnchor.constraint(
            equalTo: wakeUpCapsLabel.bottomAnchor, constant: AppSpacing.sp6
        )
        heroPin.priority = .defaultHigh

        NSLayoutConstraint.activate([
            block.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            heroPin,
            block.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: inset),
            block.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -inset)
        ])
    }

    private func makeNoBalanceDisabledCard() -> SPSnoozePrice {
        let card = SPSnoozePrice(
            price: Decimal(viewModel.currentPenalty),
            minutes: viewModel.alarm.snoozeMinutes,
            tone: .warn,
            hint: "Недостаточно средств"
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
            title: "Пополнить",
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
        // alarms show the correct disabled value even after snoozeCount has
        // bumped the next penalty.
        if let card = noBalanceSnoozeCard {
            card.update(
                price: Decimal(viewModel.currentPenalty),
                minutes: viewModel.alarm.snoozeMinutes,
                hint: "Недостаточно средств"
            )
        }
        noBalanceContainer?.isHidden = !needsNoBalance
        noBalanceCenterBlock?.isHidden = !needsNoBalance
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
            Task { @MainActor in
                await StoreKitService.shared.purchase(product)
            }
            return
        }

        // Product list hasn't loaded yet — fall back to a direct top-up.
        AppLogger.storeKit.notice(
            "noBalanceApplePayTapped: product \(productID, privacy: .public) not loaded — fallback to topUp"
        )
        let amount = Double(Self.noBalanceDisplayAmount)
        if BalanceService.shared.topUp(amount: amount) {
            return
        }
        noBalancePurchaseInFlight = false
        applePayNoBalanceButton?.isEnabled = true
        presentNoBalancePurchaseFailureAlert(
            message: StoreKitService.ledgerLockedFailureMessage
        )
    }

    /// "Выбрать другую сумму" tap. Routes to the presets bottom sheet.
    @objc func noBalanceChooseAmountTapped() {
        presentTopUpSheet()
    }

    // MARK: - Helpers

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

// MARK: - Center block storage
//
// Extending the host VC with a stored property is illegal in Swift, so we
// route the "Баланса не осталось" center block through an associated-object
// keyed accessor. Single storage slot keyed by a unique pointer; reads /
// writes happen on the main thread only (firing screen is main-only).

private var noBalanceCenterBlockKey: UInt8 = 0

extension AlarmFiringViewController {
    /// Reference to the center "Баланса не осталось" pill + body stack. We
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
