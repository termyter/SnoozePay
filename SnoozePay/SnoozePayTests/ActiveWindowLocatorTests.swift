import XCTest
@testable import SnoozePay

/// A scene candidate whose activation state the test decides.
///
/// `UIWindowScene` cannot be instantiated — the system hands them out — and the
/// test host owns exactly one, permanently foreground-active. So the only way
/// to observe "there are three scenes and the active one is not the first" is
/// to feed the selection candidates it can read the state off, which is why
/// ``ActiveWindowLocator/preferredScene(among:activationState:)`` is generic
/// over the candidate and takes the state as a parameter rather than reaching
/// for `UIApplication.shared` itself (#795).
private struct SceneCandidate {
    let name: String
    let activationState: UIScene.ActivationState
}

/// The window half of the same idea: `isKeyWindow` is read-only on `UIWindow`
/// and there is one key window per app, so "two candidates, the second is key"
/// is only stageable through a stand-in. The live property is covered
/// separately by `testPreferredWindow_readsTheLiveIsKeyWindowFlag`, which uses
/// real windows — the stand-ins prove the choice, the real one proves it is
/// wired to the flag that matters.
private struct WindowCandidate {
    let name: String
    let isKeyWindow: Bool
}

/// The selection that decides where an alert or the firing screen lands.
///
/// Four sites used to answer it with `connectedScenes…first` and
/// `windows.first`, neither of which is ordered: the presentation went to an
/// arbitrary window and on a single-window iPhone that is invisible — the alert
/// shows up, the #752 read-back confirms it, and nothing distinguishes the case
/// where it landed in a window nobody is looking at. So the failures worth
/// guarding are the two directions of the choice AND both fallbacks, since a
/// selection that is merely stricter (foreground-active only, key window only)
/// turns background notification delivery — where neither exists — into a
/// dropped alert, which is worse than the bug it fixes.
@MainActor
final class ActiveWindowLocatorTests: XCTestCase {

    /// Restored in `tearDown`: a suite that takes key status and never hands it
    /// back leaves every later presentation aimed at a window nobody is looking
    /// at (#728).
    private var previousKeyWindow: UIWindow?

    override func tearDown() {
        previousKeyWindow?.makeKeyAndVisible()
        previousKeyWindow = nil
        super.tearDown()
    }

    // MARK: - Scene selection

    func testPreferredScene_picksTheForegroundActiveOne_notTheFirstInTheList() {
        let scenes = [
            SceneCandidate(name: "background", activationState: .background),
            SceneCandidate(name: "inactive", activationState: .foregroundInactive),
            SceneCandidate(name: "active", activationState: .foregroundActive)
        ]

        let picked = ActiveWindowLocator.preferredScene(among: scenes, activationState: \.activationState)

        XCTAssertEqual(
            picked?.name, "active",
            """
            the scene the user is looking at has to win over list order; \
            picking «\(picked?.name ?? "nil")» is the pre-#795 `.first`, which \
            happened to be right only because iPhone has one scene
            """
        )
    }

    func testPreferredScene_withNoActiveScene_fallsBackToTheFirst() {
        let scenes = [
            SceneCandidate(name: "backgrounded", activationState: .background),
            SceneCandidate(name: "also backgrounded", activationState: .background)
        ]

        let picked = ActiveWindowLocator.preferredScene(among: scenes, activationState: \.activationState)

        XCTAssertEqual(
            picked?.name, "backgrounded",
            """
            notification delivery runs with the app in the background, where NO \
            scene is foreground-active; answering nil there would turn «wrong \
            window» into «no alert at all», the exact regression #752 closed
            """
        )
    }

    func testPreferredScene_withSeveralActive_takesTheFirstActiveOne() {
        let scenes = [
            SceneCandidate(name: "inactive", activationState: .foregroundInactive),
            SceneCandidate(name: "first active", activationState: .foregroundActive),
            SceneCandidate(name: "second active", activationState: .foregroundActive)
        ]

        let picked = ActiveWindowLocator.preferredScene(among: scenes, activationState: \.activationState)

        XCTAssertEqual(
            picked?.name, "first active",
            "two active scenes (Stage Manager) must resolve deterministically, not by whichever came back first"
        )
    }

    func testPreferredScene_withNoScenes_returnsNil() {
        let picked = ActiveWindowLocator.preferredScene(
            among: [SceneCandidate](), activationState: \.activationState
        )

        XCTAssertNil(
            picked,
            "no scene attached yet is the cold-launch race the callers defer on; it must stay distinguishable"
        )
    }

    // MARK: - Window selection

    func testPreferredWindow_picksTheKeyWindow_notTheFirstInTheList() {
        let windows = [
            WindowCandidate(name: "offscreen", isKeyWindow: false),
            WindowCandidate(name: "key", isKeyWindow: true)
        ]

        let picked = ActiveWindowLocator.preferredWindow(among: windows, isKeyWindow: \.isKeyWindow)

        XCTAssertEqual(
            picked?.name, "key",
            """
            a scene can carry more than one window (a presented system window, a \
            second window under Stage Manager); presenting into «\(picked?.name ?? "nil")» \
            logs ALARM-752-ALERT-SHOWN for an alert the user never sees
            """
        )
    }

    func testPreferredWindow_withNoKeyWindow_fallsBackToTheFirst() {
        let windows = [
            WindowCandidate(name: "only", isKeyWindow: false),
            WindowCandidate(name: "other", isKeyWindow: false)
        ]

        let picked = ActiveWindowLocator.preferredWindow(among: windows, isKeyWindow: \.isKeyWindow)

        XCTAssertEqual(
            picked?.name, "only",
            "a backgrounded app has no key window either — same reason the scene fallback exists"
        )
    }

    func testPreferredWindow_withNoWindows_returnsNil() {
        let picked = ActiveWindowLocator.preferredWindow(among: [WindowCandidate](), isKeyWindow: \.isKeyWindow)

        XCTAssertNil(
            picked,
            """
            a scene without windows must read as «nothing to present on» rather \
            than crash or invent one: it is the second half of the cold-launch race
            """
        )
    }

    // MARK: - Wiring to the live UIKit flags

    /// The stand-in tests above would pass just as well against a selection
    /// wired to the wrong property, since they supply the property themselves.
    /// This one hands the locator real `UIWindow`s and lets it read
    /// `isKeyWindow` off UIKit.
    func testPreferredWindow_readsTheLiveIsKeyWindowFlag() {
        previousKeyWindow = currentKeyWindow()
        guard let scene = hostWindowScene() else { return }

        let plainWindow = makeWindow(in: scene)
        let keyWindow = makeWindow(in: scene)
        keyWindow.makeKeyAndVisible()

        XCTAssertTrue(
            keyWindow.isKeyWindow,
            "test precondition: the window under assertion has to actually hold key status"
        )

        // A closure rather than `\.isKeyWindow`: forming a key path to a
        // main-actor-isolated UIKit property is a concurrency diagnostic, and
        // the stub tests above already cover the key-path form on a plain type.
        let picked = ActiveWindowLocator.preferredWindow(
            among: [plainWindow, keyWindow], isKeyWindow: { $0.isKeyWindow }
        )

        XCTAssertTrue(
            picked === keyWindow,
            "the selection has to read UIKit's own key flag, not merely prefer some property named like it"
        )

        detach(plainWindow, keyWindow)
    }

    /// And the composition: the entry point the four call sites use returns the
    /// root of the window the selection picked, over the live scene list.
    func testRootViewController_amongLiveScenes_returnsTheKeyWindowsRoot() {
        previousKeyWindow = currentKeyWindow()
        guard let scene = hostWindowScene() else { return }

        let root = UIViewController()
        let window = makeWindow(in: scene)
        window.rootViewController = root
        window.makeKeyAndVisible()

        XCTAssertTrue(
            window.isKeyWindow,
            "test precondition: the window whose root is under assertion has to hold key status"
        )

        let picked = ActiveWindowLocator.rootViewController(among: Array(UIApplication.shared.connectedScenes))

        XCTAssertTrue(
            picked === root,
            """
            the key window's root is what the user is looking at; returning \
            another window's root is the silent miss #795 is about
            """
        )

        detach(window)
    }

    // MARK: - Helpers

    private func currentKeyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }

    /// The test host's scene. Reported rather than force-unwrapped: a host
    /// without one means the suite is running somewhere it cannot assert
    /// anything, and that should read as a failure, not a crash.
    private func hostWindowScene() -> UIWindowScene? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        XCTAssertNotNil(scene, "test precondition: the test host must have a window scene")
        return scene
    }

    /// Attached to the scene explicitly: an unattached window is not in
    /// `windowScene.windows`, so the composition test would be asserting over a
    /// list its own window never joined.
    private func makeWindow(in scene: UIWindowScene) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.windowScene = scene
        // A window UIKit is asked to make key without a root controller draws a
        // console complaint and is a state the app never ships; the tests that
        // need a specific root overwrite this one.
        window.rootViewController = UIViewController()
        return window
    }

    private func detach(_ windows: UIWindow...) {
        for window in windows {
            window.rootViewController = nil
            window.isHidden = true
            window.windowScene = nil
        }
    }
}
