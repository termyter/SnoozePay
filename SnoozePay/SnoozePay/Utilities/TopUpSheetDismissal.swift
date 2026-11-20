import UIKit
import os

extension UIViewController {

    /// Closes a top-up sheet at the end of its success window (#1189, #1190).
    ///
    /// Through the presenter: `dismiss` on the sheet closes only what the sheet
    /// presents, so while its own alert is up only that alert would go. The
    /// presenter's `dismiss` also takes down everything above the sheet, so
    /// anything other than the sheet's own alert makes it skip, for example the
    /// firing screen an alarm put over the deposit sheet. The sheet then keeps its
    /// success state, and the line names the controller directly above it.
    func dismissTopUpSheetAfterSuccess(ownAlert: UIViewController?) {
        if let above = presentedViewController, above !== ownAlert || above.presentedViewController != nil {
            AppLogger.emit(
                .ui, .error, "\(type(of: self)): success dismissal skipped, \(type(of: above)) is presented above it"
            )
            return
        }
        (presentingViewController ?? self).dismiss(animated: true)
    }
}
