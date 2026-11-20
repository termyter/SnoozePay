import StoreKit
import UIKit

/// Owns direct top-up feedback independently of the firing screen's audio lifecycle.
final class AlarmFiringNoBalancePurchase {
    weak var controller: AlarmFiringViewController?
    let dispatch: ((String) -> Void)?
    private let offerProvider: ((String) -> TopUpOffer?)?
    var renderedPrice: String?
    private let center: NotificationCenter
    private let beginFeedback: () -> Void
    private let endFeedback: () -> Void
    private var balanceToken: NSObjectProtocol?
    private var catalogToken: NSObjectProtocol?
    private var terminalTokens: [NSObjectProtocol] = []
    private var observingFeedback = false

    init(
        controller: AlarmFiringViewController, center: NotificationCenter = .default,
        dispatch: ((String) -> Void)? = nil, offerProvider: ((String) -> TopUpOffer?)? = nil,
        beginFeedback: (() -> Void)? = nil,
        endFeedback: (() -> Void)? = nil
    ) {
        self.controller = controller
        self.center = center
        self.dispatch = dispatch
        self.offerProvider = offerProvider
        self.beginFeedback = beginFeedback ?? { StoreKitService.shared.beginObservingPurchaseFeedback() }
        self.endFeedback = endFeedback ?? { StoreKitService.shared.endObservingPurchaseFeedback() }
    }

    deinit {
        if let balanceToken { center.removeObserver(balanceToken) }
        if let catalogToken { center.removeObserver(catalogToken) }
        terminalTokens.forEach { center.removeObserver($0) }
        if observingFeedback { endFeedback() }
    }

    /// The pack the direct CTA quotes and buys: the one the amount sheet opens on
    /// for the same wallet and next charge (#652), never a fixed SKU, chosen
    /// from the same rows the sheet would offer (#1112).
    ///
    /// Sufficiency is reckoned in the locked price's currency (#1142): a
    /// pristine wallet on a dollar storefront picks the minimal dollar pack. A
    /// price the wallet can no longer hold is stranded and the next pass hides
    /// the CTA, but a tap before that pass still reads a pack here, and the
    /// gate refuses it as below (#1181).
    ///
    /// `acceptsPurchase` only ranks the packs; it never empties the pick. When
    /// the wallet refuses the whole storefront (foreign currency, unreadable
    /// ledger), a refused pack stands in, so the CTA stays tappable and the
    /// tap's `prePurchaseRefusal(in:)` names the refusal (#1174).
    var offer: TopUpOffer? {
        guard let model = controller?.viewModel else { return nil }
        let currency = model.priceCurrency
        let rows = FiringTopUpBottomSheetViewController.offeredPresets(
            offer: offer(for:), balance: model.balance, price: model.currentPenalty,
            walletCurrency: currency, acceptsPurchase: model.acceptsPurchase(in:)
        )
        let offers = rows.compactMap { offer(for: $0.productID) }
        return FiringTopUpCopy.preselectedOffer(
            offers: offers, balance: model.balance, price: model.currentPenalty,
            walletCurrency: currency, acceptsPurchase: model.acceptsPurchase(in:)
        )
    }

    private func offer(for productID: String) -> TopUpOffer? {
        if let offerProvider {
            let offer = offerProvider(productID)
            return offer?.productID == productID ? offer : nil
        }
        return StoreKitService.shared.products.first(where: { $0.id == productID }).flatMap(TopUpOffer.init(product:))
    }

    func observeBalance() {
        guard balanceToken == nil else { return }
        balanceToken = center.addObserver(
            forName: BalanceService.balanceChangedNotification, object: nil, queue: .main
        ) { [weak controller] _ in
            // A balance change does not end this tap; only StoreKit's result for it does.
            controller?.updateUI()
        }
        catalogToken = center.addObserver(
            forName: StoreKitService.productsLoadedNotification, object: nil, queue: .main
        ) { [weak controller] _ in controller?.refreshNoBalanceCatalog() }
    }

    func observeFeedback() {
        guard !observingFeedback else { return }
        observingFeedback = true
        let messageKey = StoreKitService.messageUserInfoKey
        terminalTokens = [
            center.addObserver(
                forName: StoreKitService.purchaseCancelledNotification, object: nil, queue: .main
            ) { [weak self] _ in self?.finish() },
            center.addObserver(
                forName: StoreKitService.purchaseCompletedNotification, object: nil, queue: .main
            ) { [weak self] _ in
                guard let self, self.finish() else { return }
                self.controller?.updateUI()
            },
            center.addObserver(
                forName: StoreKitService.purchaseFailedNotification, object: nil, queue: .main
            ) { [weak self] note in
                guard let self, self.finish() else { return }
                self.controller?.presentNoBalancePurchaseFailureAlert(message: note.userInfo?[messageKey] as? String)
            },
            // Ask to Buy / SCA ends this tap (#1183). An approval still credits
            // through `Transaction.updates`; the balance observer redraws then.
            center.addObserver(
                forName: StoreKitService.purchasePendingNotification, object: nil, queue: .main
            ) { [weak self] _ in
                guard let self, self.finish() else { return }
                self.controller?.presentNoBalancePurchasePendingAlert()
            }
        ]
        beginFeedback()
    }

    @discardableResult
    func finish() -> Bool {
        guard let controller, controller.noBalancePurchaseInFlight else { return false }
        controller.noBalancePurchaseInFlight = false
        controller.refreshNoBalanceCatalog()
        // The link's own tap guard, as `refreshNoBalanceCatalog` gates the CTA:
        // a late result after Stop must not wake a link that does nothing (#1183).
        controller.chooseAmountLink?.isEnabled = !controller.viewModel.finishRequested
        terminalTokens.forEach { center.removeObserver($0) }
        terminalTokens.removeAll()
        if observingFeedback {
            observingFeedback = false
            endFeedback()
        }
        return true
    }
}

private var noBalancePurchaseKey: UInt8 = 0

extension AlarmFiringViewController {
    var noBalancePurchase: AlarmFiringNoBalancePurchase {
        get {
            if let owner = objc_getAssociatedObject(self, &noBalancePurchaseKey) as? AlarmFiringNoBalancePurchase {
                return owner
            }
            let owner = AlarmFiringNoBalancePurchase(controller: self)
            noBalancePurchase = owner
            return owner
        }
        set { objc_setAssociatedObject(self, &noBalancePurchaseKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}
