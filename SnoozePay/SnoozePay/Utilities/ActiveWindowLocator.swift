import UIKit

/// Finds the root view controller of the window the user is actually looking
/// at, for the code paths that have to put something on screen from outside a
/// view controller — an alert from `AppDelegate`, the firing screen from
/// `AlarmFiringPresenter`.
///
/// Four sites used to resolve it by hand, all four the same way:
/// `connectedScenes.compactMap { $0 as? UIWindowScene }.first` and then
/// `windowScene.windows.first`. Neither collection promises an order, so both
/// `.first` calls picked an arbitrary member — an arbitrary scene, then an
/// arbitrary window of it. On a one-window iPhone that is indistinguishable
/// from the right answer, which is why it survived every run; with a second
/// window (Stage Manager, an iPad side-by-side scene, a transient system
/// window) it silently aims the presentation somewhere nobody is looking, and
/// the #752 read-back then reports the alert as SHOWN because it genuinely was
/// — in a window off screen.
///
/// # Why both fallbacks are non-negotiable
///
/// The selection prefers the foreground-active scene and that scene's key
/// window, but falls back to "any" for each. These paths run from notification
/// delivery, which happens while the app is backgrounded: there is then no
/// `.foregroundActive` scene at all, and no key window. Turning "no active
/// scene" into "no window", i.e. into a dropped alert, would trade a
/// wrong-window bug for a no-alert bug — strictly worse, and exactly what #752
/// was about.
///
/// # Why the selection takes its candidates as a parameter
///
/// So it can be tested. `UIApplication.shared.connectedScenes` cannot be staged
/// from a unit test — there is one scene and it belongs to the test host — so a
/// helper reaching for it directly would be as untestable as the four copies it
/// replaces (the same reason `showAlarmDataCorruptedAlert(on:message:)` was
/// split out in #752). The picking is generic over the candidate type with the
/// one property it reads passed in, so `ActiveWindowLocatorTests` can hand it
/// scenes that are active and inactive on demand. `UIApplication.shared` is
/// touched only by the convenience entry point below, which has nothing left in
/// it to get wrong.
enum ActiveWindowLocator {

    /// The scene to present on: the foreground-active one, else the first
    /// available. `nil` only when `scenes` is empty (no scene attached yet —
    /// the cold-launch race the callers already handle).
    static func preferredScene<Scene>(
        among scenes: [Scene],
        activationState: (Scene) -> UIScene.ActivationState
    ) -> Scene? {
        scenes.first { activationState($0) == .foregroundActive } ?? scenes.first
    }

    /// The window to present in: the key one, else the first available. `nil`
    /// only when the scene has no windows.
    static func preferredWindow<Window>(
        among windows: [Window],
        isKeyWindow: (Window) -> Bool
    ) -> Window? {
        windows.first(where: isKeyWindow) ?? windows.first
    }

    /// Root view controller of the preferred window of the preferred scene
    /// among `scenes`, or `nil` when no scene carries a window with a root yet.
    @MainActor
    static func rootViewController(among scenes: [UIScene]) -> UIViewController? {
        let windowScenes = scenes.compactMap { $0 as? UIWindowScene }
        guard
            let scene = preferredScene(among: windowScenes, activationState: { $0.activationState }),
            let window = preferredWindow(among: scene.windows, isKeyWindow: { $0.isKeyWindow })
        else {
            return nil
        }
        return window.rootViewController
    }

    /// ``rootViewController(among:)`` over the live scene list. The one place
    /// that reads `UIApplication.shared`, kept a single line so the part worth
    /// asserting stays in the function above.
    @MainActor
    static func rootViewController() -> UIViewController? {
        rootViewController(among: Array(UIApplication.shared.connectedScenes))
    }
}
