import UIKit
import os

extension UIViewController {

    /// Closes a top-up sheet at the end of its success window (#1189, #1190).
    ///
    /// Through the presenter: `dismiss` on the sheet closes only what the sheet
    /// presents, so while its own alert is up only that alert would go. The
    /// presenter's `dismiss` also takes down everything above the sheet, so
    /// anything other than the sheet's own alert makes it skip, for example the
    /// firing screen an alarm put over the deposit sheet or over its notice.
    ///
    /// The sheet then stays in its success state and nothing retries. The line is
    /// the only trace of that, so it names the controller at the top of the chain,
    /// the actual cause, rather than the sheet's own alert under it.
    func dismissTopUpSheetAfterSuccess(ownAlert: UIViewController?) {
        if let above = presentedViewController, above !== ownAlert || above.presentedViewController != nil {
            var top = above
            while let next = top.presentedViewController { top = next }
            let place = above === ownAlert ? "over the sheet's own alert" : "above it"
            AppLogger.emit(
                .ui, .error,
                "\(type(of: self)): success dismissal skipped, \(topUpLogName(of: top)) is presented \(place); "
                    + "sheet left in success state, not retried"
            )
            return
        }
        (presentingViewController ?? self).dismiss(animated: true)
    }
}

/// An alert's type alone does not tell restore, warning and notice apart: add
/// its accessibility identifier, or its title when it has none.
private func topUpLogName(of controller: UIViewController) -> String {
    guard let alert = controller as? UIAlertController else { return "\(type(of: controller))" }
    let identifier = alert.viewIfLoaded?.accessibilityIdentifier
    guard let label = [identifier, alert.title].compactMap({ $0 }).first(where: { !$0.isEmpty }) else {
        return "UIAlertController"
    }
    return "UIAlertController(\(label))"
}
