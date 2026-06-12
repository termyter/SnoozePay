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
            title: "Запрос отправлен",
            message: "Если у вас есть предыдущие покупки, баланс обновится автоматически в течение нескольких секунд.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func presentRestoreError(_ error: Error) {
        let alert = UIAlertController(
            title: "Не удалось восстановить покупки",
            message: StoreKitRestoreErrorCopy.message(for: error),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

/// Translates StoreKit / SKError / URLError failures into actionable
/// Russian copy. Kept as a standalone enum so the per-error matching doesn't
/// push any host controller's cyclomatic complexity over the project's lint
/// threshold. Each helper handles one error family; the public
/// `message(for:)` walks them in priority order.
enum StoreKitRestoreErrorCopy {

    /// Common networking copy reused by URL / SK / StoreKit network branches.
    private static let networkAdvice = "Проверьте подключение к интернету и попробуйте снова."

    static func message(for error: Error) -> String {
        if let typed = storeKitErrorMessage(error) { return typed }
        if let typed = skErrorMessage(error) { return typed }
        if let typed = urlErrorMessage(error) { return typed }
        return "\(error.localizedDescription)\n\nЕсли проблема повторяется, свяжитесь с поддержкой."
    }

    private static func storeKitErrorMessage(_ error: Error) -> String? {
        guard let storeKitError = error as? StoreKitError else { return nil }
        switch storeKitError {
        case .userCancelled:
            return "Действие отменено."
        case .networkError:
            return networkAdvice
        case .notAvailableInStorefront:
            return "Покупки временно недоступны в вашем регионе."
        case .notEntitled:
            return "Войдите в Apple ID в Настройках и попробуйте снова."
        default:
            return nil
        }
    }

    private static func skErrorMessage(_ error: Error) -> String? {
        guard let skError = error as? SKError else { return nil }
        switch skError.code {
        case .paymentNotAllowed:
            return "В вашем Apple ID запрещены покупки. Проверьте настройки экранного времени."
        case .cloudServiceNetworkConnectionFailed,
             .cloudServicePermissionDenied,
             .cloudServiceRevoked:
            return "Проверьте подключение к интернету и доступ к iCloud в Настройках."
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
