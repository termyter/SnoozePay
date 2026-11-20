import CoreFoundation
import Foundation
import UIKit
import os

/// Presentation snapshot of an already credited amount, never a selected SKU
/// or the wallet total. Currency is captured from the wallet after credit.
struct TopUpSuccessReceipt {
    let amount: Double
    let currency: Currency

    init?(amount: Double, currency: Currency) {
        guard amount.isFinite, amount > 0 else { return nil }
        self.amount = amount
        self.currency = currency
    }

    init?(eventAmount: Any?, currency: Currency) {
        guard let number = eventAmount as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              let amount = eventAmount as? Double else { return nil }
        self.init(amount: amount, currency: currency)
    }
}

/// One scheduling seam for the existing two-second success dismissal.
typealias TopUpSuccessDismissal = @MainActor (TimeInterval, @escaping @MainActor @Sendable () -> Void) -> Void

/// Closes a top-up sheet at the end of its success window (#1189, #1190).
///
/// Through the presenter, so the sheet goes even while it shows its own alert:
/// `dismiss` on a presenter closes only its presented child. Anything else above
/// the sheet, such as the firing screen an alarm put over the deposit sheet, is
/// not the sheet's to close: the presenter's `dismiss` would take it down too,
/// with the alarm ringing. Then the sheet stays in its success state and says why.
@MainActor
func dismissTopUpSheetAfterSuccess(_ sheet: UIViewController, ownAlert: UIViewController?) {
    if let above = sheet.presentedViewController, above !== ownAlert || above.presentedViewController != nil {
        let cover = above.presentedViewController.map { type(of: $0) } ?? type(of: above)
        AppLogger.emit(.ui, .error, "\(type(of: sheet)): success dismissal skipped, \(cover) is presented above it")
        return
    }
    (sheet.presentingViewController ?? sheet).dismiss(animated: true)
}
