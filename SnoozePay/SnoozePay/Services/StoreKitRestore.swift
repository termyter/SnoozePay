import StoreKit
import UIKit
import os

/// Sends an explicit App Store sync request; it does not credit purchases.
/// Verified transaction processing remains owned by `StoreKitService`.
extension UIViewController {

    /// Completion means the sync request returned, not that money was credited.
    /// The returned task also lets callers wait for the request's terminal result.
    @discardableResult
    func performStoreKitRestore(
        onRequestCompleted: (@MainActor () -> Void)? = nil,
        sync: @escaping @MainActor () async throws -> Void = { try await AppStore.sync() }
    ) -> Task<Void, Never> {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await sync()
                AppLogger.storeKit.notice("Restore request completed")
                onRequestCompleted?()
                self.presentRestoreSuccess()
            } catch {
                if restoreRequestWasCancelled(error) {
                    AppLogger.storeKit.notice("Restore request cancelled")
                    return
                }
                AppLogger.storeKit.error("Restore request failed")
                self.presentRestoreError(error)
            }
        }
    }

    private func presentRestoreSuccess() {
        let alert = UIAlertController(
            title: Localized.text("deposit.restore.success.title"),
            message: Localized.text("deposit.restore.success.message"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: Localized.text("common.button.ok"), style: .default))
        present(alert, animated: true)
    }

    private func presentRestoreError(_ error: Error) {
        let alert = UIAlertController(
            title: Localized.text("deposit.restore.error.title"),
            message: StoreKitRestoreErrorCopy.message(for: error),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: Localized.text("common.button.ok"), style: .default))
        present(alert, animated: true)
    }
}

/// Cancellation codes are meaningful only within their own error domain.
private func restoreRequestWasCancelled(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    if let storeKitError = error as? StoreKitError, case .userCancelled = storeKitError { return true }
    let systemError = error as NSError
    return (systemError.domain == NSCocoaErrorDomain && systemError.code == NSUserCancelledError)
        || (systemError.domain == SKErrorDomain && systemError.code == SKError.Code.paymentCancelled.rawValue)
}

/// Translates StoreKit / SKError / URLError failures into actionable copy from
/// `Localizable.xcstrings`. Kept as a standalone enum so the per-error matching doesn't
/// push any host controller's cyclomatic complexity over the project's lint
/// threshold. Each helper handles one error family; the public
/// `message(for:)` walks them in priority order.
enum StoreKitRestoreErrorCopy {

    /// Common networking copy reused by URL / SK / StoreKit network branches.
    ///
    /// Computed rather than stored so the only cache in the path is
    /// `Localized.bundle` — the single place #596 has to touch when it
    /// collapses that bundle to `.main`. No runtime effect today: the language
    /// cannot change while the app runs, and `AppLocale.display` is hardcoded
    /// to `ru_RU` regardless.
    private static var networkAdvice: String { Localized.text("deposit.restore.error.network") }

    static func message(for error: Error) -> String {
        if let typed = storeKitErrorMessage(error) { return typed }
        if let typed = skErrorMessage(error) { return typed }
        if let typed = urlErrorMessage(error) { return typed }
        // The system's own description leads the sentence, so it is a
        // substitution rather than a concatenation — the suffix may need to
        // precede it in another language.
        return Localized.format("deposit.restore.error.generic", error.localizedDescription)
    }

    private static func storeKitErrorMessage(_ error: Error) -> String? {
        guard let storeKitError = error as? StoreKitError else { return nil }
        switch storeKitError {
        case .userCancelled:
            return Localized.text("deposit.restore.error.cancelled")
        case .networkError:
            return networkAdvice
        case .notAvailableInStorefront:
            return Localized.text("deposit.restore.error.storefront")
        case .notEntitled:
            return Localized.text("deposit.restore.error.not_entitled")
        default:
            return nil
        }
    }

    private static func skErrorMessage(_ error: Error) -> String? {
        guard let skError = error as? SKError else { return nil }
        switch skError.code {
        case .paymentNotAllowed:
            return Localized.text("deposit.restore.error.payment_not_allowed")
        case .cloudServiceNetworkConnectionFailed,
             .cloudServicePermissionDenied,
             .cloudServiceRevoked:
            return Localized.text("deposit.restore.error.icloud")
        default:
            return nil
        }
    }

    private static func urlErrorMessage(_ error: Error) -> String? {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain { return networkAdvice }
        guard let urlError = error as? URLError else { return nil }
        switch urlError.code {
        case .notConnectedToInternet,
             .networkConnectionLost,
             .timedOut,
             .cannotConnectToHost:
            return networkAdvice
        default:
            return nil
        }
    }
}
