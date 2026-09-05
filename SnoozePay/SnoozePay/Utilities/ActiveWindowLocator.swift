import UIKit
import os

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
/// # Why only windows that already carry a root are candidates
///
/// Preferring the key window is not a free strictening, and the first revision
/// of this file claimed it was ("no worse than the old `.first`"). It is worse
/// on exactly one state, and that state is ordinary: the app's own window is
/// created first, while transient system windows — the keyboard's, an alert's —
/// attach later and can hold key status while carrying NO root view controller.
/// The old `.first` practically never landed on those; `first(where:
/// \.isKeyWindow)` aims straight at them. Reading a nil root off the winner
/// would then drop the presentation with a perfectly good sibling window
/// standing next to it: the firing screen never rises, `AlarmFiringPresenter`
/// stops the audio, and an alarm goes silent because a keyboard was up.
///
/// So the preference runs over the windows that can actually host a
/// presentation, and "the key one, else the first" picks among those.
///
/// # Why both fallbacks are non-negotiable, and why they now say so
///
/// The selection prefers the foreground-active scene and that scene's key
/// window, but falls back to "any" for each. These paths run from notification
/// delivery, which happens while the app is backgrounded: there is then no
/// `.foregroundActive` scene at all, and no key window. Turning "no active
/// scene" into "no window", i.e. into a dropped alert, would trade a
/// wrong-window bug for a no-alert bug — strictly worse, and exactly what #752
/// was about.
///
/// Each fallback therefore leaves a line instead of taking its decision
/// silently. Without one, `ALARM-752-ALERT-SHOWN` reads identically whether the
/// alert landed in the key window of the scene the user is looking at or in an
/// arbitrary one of three — which is the question #752/#795 exist to answer. At
/// `notice` (`.default`), not `error`: backgrounded delivery is the expected
/// state here, not a failure.
///
/// # Two layers, and why the second one is not pure
///
/// ``preferredScene(among:activationState:)`` and
/// ``preferredWindow(among:isKeyWindow:)`` are the choice and nothing else.
/// ``hostingScene(among:activationState:)`` and
/// ``hostingWindow(among:isKeyWindow:hasRoot:)`` wrap them with the two things
/// nobody downstream can reconstruct: WHICH empty state was hit, and whether a
/// fallback fired. The logging sits there rather than in
/// ``rootViewController(among:)`` because that one needs live UIKit, and a
/// notice only a device can provoke is a notice no test pins.
///
/// # Why the selection takes its candidates as a parameter
///
/// So it can be tested. `UIApplication.shared.connectedScenes` cannot be staged
/// from a unit test — there is one scene and it belongs to the test host — so a
/// helper reaching for it directly would be as untestable as the four copies it
/// replaces (the same reason `showAlarmDataCorruptedAlert(on:message:)` was
/// split out in #752). The picking is generic over the candidate type with the
/// properties it reads passed in, so `ActiveWindowLocatorTests` can hand it
/// scenes that are active and inactive, and windows with and without a root, on
/// demand. `UIApplication.shared` is touched only by the convenience entry
/// point below, which has nothing left in it to get wrong.
enum ActiveWindowLocator {

    /// Why there is nothing to present on.
    ///
    /// Three states, not one. A single `nil` folded "no scene attached yet"
    /// (cold launch), "the selected scene has no windows" and "no window of it
    /// carries a root" into one log line, and a reader who fixes by the reason
    /// would go hunting rootless windows in a process that has no windows at
    /// all. The raw value is the sentence that reaches the log, so the three
    /// states stay three greps.
    enum Miss: String, Error {
        case noScene = "no window scene attached yet"
        case noWindows = "the selected window scene has no windows"
        case noHostingWindow = "no window in the selected scene has a root view controller"
    }

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
    /// only when `windows` is empty.
    ///
    /// Callers pass the windows that can host a presentation, not every window
    /// of the scene — see the type comment on why a key window is not
    /// automatically a usable one.
    static func preferredWindow<Window>(
        among windows: [Window],
        isKeyWindow: (Window) -> Bool
    ) -> Window? {
        windows.first(where: isKeyWindow) ?? windows.first
    }

    /// ``preferredScene(among:activationState:)`` plus the record: `.noScene`
    /// when there is none, and a `notice` when the foreground-active preference
    /// had to fall back.
    static func hostingScene<Scene>(
        among scenes: [Scene],
        activationState: (Scene) -> UIScene.ActivationState
    ) -> Result<Scene, Miss> {
        guard let scene = preferredScene(among: scenes, activationState: activationState) else {
            return .failure(.noScene)
        }
        if activationState(scene) != .foregroundActive {
            AppLogger.emit(
                .appDelegate, .default,
                """
                window-selection: no foregroundActive scene among \(scenes.count) — \
                presenting in the first attached one
                """
            )
        }
        return .success(scene)
    }

    /// The window that can take the presentation: the key one among those
    /// carrying a root, else the first of them.
    ///
    /// Separates the two empty states nothing downstream can tell apart — a
    /// scene with no windows at all, and a scene whose windows are all rootless
    /// — and leaves a `notice` when the key-window preference had to fall back,
    /// which is what a key-but-rootless system window produces.
    static func hostingWindow<Window>(
        among windows: [Window],
        isKeyWindow: (Window) -> Bool,
        hasRoot: (Window) -> Bool
    ) -> Result<Window, Miss> {
        guard !windows.isEmpty else {
            return .failure(.noWindows)
        }
        let hosting = windows.filter(hasRoot)
        guard let window = preferredWindow(among: hosting, isKeyWindow: isKeyWindow) else {
            return .failure(.noHostingWindow)
        }
        if !isKeyWindow(window) {
            AppLogger.emit(
                .appDelegate, .default,
                """
                window-selection: no key window with a root among \(windows.count) \
                in the selected scene — presenting in the first that has one
                """
            )
        }
        return .success(window)
    }

    /// Root view controller of the hosting window of the preferred scene among
    /// `scenes`, or the ``Miss`` naming which of the three empty states was hit.
    @MainActor
    static func rootViewController(among scenes: [UIScene]) -> Result<UIViewController, Miss> {
        let windowScenes = scenes.compactMap { $0 as? UIWindowScene }
        let scene: UIWindowScene
        switch hostingScene(among: windowScenes, activationState: { $0.activationState }) {
        case let .failure(miss):
            return .failure(miss)
        case let .success(found):
            scene = found
        }

        let window: UIWindow
        switch hostingWindow(
            among: scene.windows,
            isKeyWindow: { $0.isKeyWindow },
            hasRoot: { $0.rootViewController != nil }
        ) {
        case let .failure(miss):
            return .failure(miss)
        case let .success(found):
            window = found
        }

        // `hostingWindow` only returns a window that passed `hasRoot`, so this
        // cannot fire; spelled out rather than force-unwrapped because a crash
        // on the alarm-firing path is the one outcome worse than a logged miss.
        guard let root = window.rootViewController else {
            return .failure(.noHostingWindow)
        }
        return .success(root)
    }

    /// ``rootViewController(among:)`` over the live scene list. The one place
    /// that reads `UIApplication.shared`, kept a single line so the part worth
    /// asserting stays in the function above.
    @MainActor
    static func rootViewController() -> Result<UIViewController, Miss> {
        rootViewController(among: Array(UIApplication.shared.connectedScenes))
    }
}
