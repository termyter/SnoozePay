import StoreKit
import UIKit
import os

/// Reusable "Restore purchases" entry point. Extracted from the retired
/// `TopUpViewController` (#281) so the single Deposit surface
/// (`DepositBottomSheetViewController`) keeps the App Store-required restore
/// affordance. `AppStore.sync()` triggers Apple's restore; the
/// `Transaction.updates` listener inside `StoreKitService` does the actual
/// crediting, and we surface typed errors with actionable Russian copy
/// instead of swallowing them (#71).
extension UIViewController {

    /// Triggers Apple's restore flow and surfaces a success / error alert.
    /// `onCredited` runs on the main actor after a successful `sync()` so the
    /// caller can refresh any visible balance UI.
    func performStoreKitRestore(onCredited: (@MainActor () -> Void)? = nil) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await AppStore.sync()
                await MainActor.run {
                    onCredited?()
                    self.presentRestoreSuccess()
                }
            } catch is CancellationError {
                return
            } catch {
                if (error as NSError).code == NSUserCancelledError { return }
                AppLogger.storeKit.error(
                    "performStoreKitRestore failed: \(error.localizedDescription, privacy: .public)"
                )
                await MainActor.run {
                    self.presentRestoreError(error)
                }
            }
        }
    }

    private func presentRestoreSuccess() {
        let alert = UIAlertController(
            title: Localized.text("deposit.restore.success.title"),
            message: Localized.text("deposit.restore.success.message"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func presentRestoreError(_ error: Error) {
        let alert = UIAlertController(
            title: Localized.text("deposit.restore.error.title"),
            message: StoreKitRestoreErrorCopy.message(for: error),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

/// Translates StoreKit / SKError / URLError failures into actionable copy from
/// `Localizable.xcstrings`. Kept as a standalone enum so the per-error matching doesn't
/// push any host controller's cyclomatic complexity over the project's lint
/// threshold. Each helper handles one error family; the public
/// `message(for:)` walks them in priority order.
enum StoreKitRestoreErrorCopy {

    /// Common networking copy reused by URL / SK / StoreKit network branches.
    ///
    /// A computed property rather than a stored one: `Localized` reads the
    /// bundle, and a `static let` would freeze the first-read language for the
    /// process lifetime.
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
