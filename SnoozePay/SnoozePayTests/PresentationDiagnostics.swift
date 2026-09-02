import UIKit

/// Describes the presentation chain hanging off `root`, printed on failure so
/// the next red run names the missing link instead of only saying one is
/// missing. A chain of just `UITabBarController` means the route never
/// presented at all; a chain that reaches the sheet with `window: nil` means it
/// fired at a presenter that had left the hierarchy and UIKit dropped it on the
/// floor — two different bugs behind one message otherwise (#618, #693).
///
/// One copy on purpose (#698): this was duplicated across the two tour suites,
/// and the only difference between the copies was how each reached its root
/// controller, so that root is the parameter.
///
/// `window: nil` covers both "the view was never loaded" and "the view is
/// loaded but attached to nothing" — for the failures this exists to explain,
/// the useful fact is that nothing in the chain can be on screen either way.
func presentationDiagnostics(rootedAt root: UIViewController?) -> String {
    var chain: [String] = []
    var current = root
    while let node = current {
        let attached = node.viewIfLoaded?.window == nil ? "window: nil" : "window: set"
        chain.append("\(type(of: node))(\(attached))")
        current = node.presentedViewController
    }
    return "presentation chain: "
        + (chain.isEmpty ? "no root view controller" : chain.joined(separator: " → "))
}
