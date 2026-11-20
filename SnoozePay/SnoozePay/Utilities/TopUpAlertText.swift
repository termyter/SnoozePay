import UIKit

/// `text` with `paragraph` added as its last paragraph, unless one of its
/// paragraphs already says it word for word: a failure delivered twice, by the
/// purchase and again by `Transaction.updates`, is read once (#1201).
func topUpParagraphs(_ text: String?, adding paragraph: String) -> String {
    let separator = "\n\n"
    guard let text, !text.isEmpty else { return paragraph }
    let says = (separator + text + separator).contains(separator + paragraph + separator)
    return says ? text : text + separator + paragraph
}

extension UIAlertController {

    /// A failure that reaches a top-up sheet while the sheet's own alert is up
    /// (#1201). UIKit presents one alert at a time, so the failure joins the one
    /// on screen: the user reads it at once, and nothing waits for an OK that a
    /// dismissal of the sheet and its alert (its success, an alarm stop) would
    /// never deliver.
    ///
    /// A titleless alert, the pending notice, takes the failure's title. Its own
    /// paragraph stays: the failure carries no transaction identity and may be
    /// another purchase's, so the approval the notice promises may still come.
    func addTopUpFailure(title: String?, message: String) {
        if self.title == nil { self.title = title }
        self.message = topUpParagraphs(self.message, adding: message)
    }

    /// Whether the alert already says `paragraph` word for word.
    func saysTopUpParagraph(_ paragraph: String) -> Bool {
        topUpParagraphs(message, adding: paragraph) == message
    }
}
