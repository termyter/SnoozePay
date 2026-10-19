import UIKit

/// Owns direct top-up feedback independently of the firing screen's audio lifecycle.
final class AlarmFiringNoBalancePurchase {
    weak var controller: AlarmFiringViewController?
    let dispatch: ((String) -> Void)?
    private let center: NotificationCenter
    private let beginFeedback: () -> Void
    private let endFeedback: () -> Void
    private var balanceToken: NSObjectProtocol?
    private var terminalTokens: [NSObjectProtocol] = []
    private var observingFeedback = false

    init(
        controller: AlarmFiringViewController, center: NotificationCenter = .default,
        dispatch: ((String) -> Void)? = nil,
        beginFeedback: @escaping () -> Void = { StoreKitService.shared.beginObservingPurchaseFeedback() },
        endFeedback: @escaping () -> Void = { StoreKitService.shared.endObservingPurchaseFeedback() }
    ) {
        self.controller = controller
        self.center = center
        self.dispatch = dispatch
        self.beginFeedback = beginFeedback
        self.endFeedback = endFeedback
    }

    deinit {
        if let balanceToken { center.removeObserver(balanceToken) }
        terminalTokens.forEach { center.removeObserver($0) }
        if observingFeedback { endFeedback() }
    }

    func observeBalance() {
        guard balanceToken == nil else { return }
        balanceToken = center.addObserver(
            forName: BalanceService.balanceChangedNotification, object: nil, queue: .main
        ) { [weak controller] _ in
            // A balance change is not a StoreKit terminal result (Ask to Buy may still be pending).
            controller?.updateUI()
        }
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
            }
        ]
        beginFeedback()
    }

    @discardableResult
    func finish() -> Bool {
        guard let controller, controller.noBalancePurchaseInFlight else { return false }
        controller.noBalancePurchaseInFlight = false
        controller.applePayNoBalanceButton?.isEnabled = true
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
