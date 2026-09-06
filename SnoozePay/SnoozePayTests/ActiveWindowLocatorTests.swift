import os
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
    /// Whether this window is a place the app may mount a full-screen
    /// controller: live that means a root view controller AND `windowLevel ==
    /// .normal` (see ``ActiveWindowLocator``). `var` with a default so the
    /// tests that only care about the key/first choice stay written the way
    /// they were; the ones about a key system window say `canHost: false` out
    /// loud.
    var canHost: Bool = true
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

        // A closure rather than `\.isKeyWindow`, matching the stub tests above.
        // An earlier revision justified this with a concurrency diagnostic that
        // does not exist: `\.isKeyWindow` typechecks clean under this target's
        // flags (`-swift-version 5 -default-isolation MainActor`). Either form
        // compiles; the closure is here for consistency, nothing more.
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

        let located = ActiveWindowLocator.rootViewController(among: Array(UIApplication.shared.connectedScenes))

        XCTAssertTrue(
            (try? located.get()) === root,
            """
            the key window's root is what the user is looking at; returning \
            another window's root is the silent miss #795 is about
            """
        )

        detach(window)
    }

    /// The regression the first revision of this PR introduced and its body
    /// denied ("no worse than the old `.first`"): a key window WITHOUT a root.
    ///
    /// The keyboard's window and an alert's window attach after the app's own
    /// and can hold key status while carrying no root controller. `.first`
    /// practically never landed on them; `first(where: \.isKeyWindow)` aims at
    /// them, and answering nil there is not "no alert this once" — it is
    /// `AlarmFiringPresenter` stopping the alarm audio and never raising the
    /// screen because the user happened to be typing.
    func testRootViewController_whenTheKeyWindowHasNoRoot_stillFindsOneToPresentIn() {
        previousKeyWindow = currentKeyWindow()
        guard let scene = hostWindowScene() else { return }

        let hostingWindow = makeWindow(in: scene)
        let root = UIViewController()
        hostingWindow.rootViewController = root

        let rootlessKeyWindow = makeWindow(in: scene)
        rootlessKeyWindow.rootViewController = nil
        rootlessKeyWindow.makeKeyAndVisible()

        let located = ActiveWindowLocator.rootViewController(among: Array(UIApplication.shared.connectedScenes))
        let rootsOnScreen = scene.windows.compactMap { $0.rootViewController }

        guard let picked = try? located.get() else {
            XCTFail(
                """
                answered «nothing to present on» with \(rootsOnScreen.count) of \
                \(scene.windows.count) windows carrying a root — a key window \
                without one must not shadow the app window standing next to it
                """
            )
            detach(hostingWindow, rootlessKeyWindow)
            return
        }

        XCTAssertTrue(
            rootsOnScreen.contains { $0 === picked },
            "the answer has to be a root of a window that actually has one, not an invented controller"
        )

        detach(hostingWindow, rootlessKeyWindow)
    }

    /// The half a root check cannot cover: a key system window that DOES carry
    /// a root.
    ///
    /// Filtering candidates by "has a root" keeps out the rootless system
    /// windows and nothing else — a window above `.normal` that carries a root
    /// passes the filter and then wins on key status, which is exactly what
    /// `first(where: \.isKeyWindow)` aims at and the old `.first` practically
    /// never reached. Whether any particular system window carries a root is
    /// not asserted here and does not matter: the app declares
    /// `UIApplicationSupportsMultipleScenes = false` and creates one window
    /// (`SceneDelegate.swift:20`), so every other window in the scene is
    /// UIKit's, and `.normal` is the right filter in both directions.
    ///
    /// Landing above `.normal` is not merely cosmetic. `AlarmFiringPresenter`
    /// would mount the firing screen over a system surface, and
    /// `isLaunchRootReady()` would read the #382 "not over the splash" gate off
    /// a root that is not the app's — answering `true` for a window that never
    /// had a splash — while `ALARM-752-ALERT-SHOWN` reports SHOWN either way.
    ///
    /// Staged on live `UIWindow`s rather than stand-ins because the property
    /// under test is the one `rootViewController(among:)` passes to `canHost`,
    /// and a stand-in would supply it instead of reading it.
    func testRootViewController_whenAnAboveNormalWindowIsKey_staysAtTheAppsOwnLevel() {
        previousKeyWindow = currentKeyWindow()
        guard let scene = hostWindowScene() else { return }

        let appWindow = makeWindow(in: scene)
        let systemWindow = makeWindow(in: scene)
        systemWindow.windowLevel = .alert
        systemWindow.makeKeyAndVisible()

        XCTAssertTrue(
            systemWindow.isKeyWindow,
            "test precondition: the above-normal window has to actually hold key status"
        )
        XCTAssertNotNil(
            systemWindow.rootViewController,
            "test precondition: this case is about a system window that DOES carry a root"
        )

        let located = ActiveWindowLocator.rootViewController(among: Array(UIApplication.shared.connectedScenes))
        let attached = scene.windows.count
        let atNormalLevel = scene.windows.filter { $0.windowLevel == UIWindow.Level.normal }.count

        guard let picked = try? located.get() else {
            XCTFail(
                """
                answered «nothing to present on» while \(attached) windows were \
                attached and \(atNormalLevel) of them sit at level .normal — \
                filtering out UIKit's overlays must not empty the candidate list
                """
            )
            detach(appWindow, systemWindow)
            return
        }

        let owner = scene.windows.first { $0.rootViewController === picked }
        let landedIn = owner.map { "a window at level \($0.windowLevel.rawValue)" } ?? "no window of this scene"
        XCTAssertEqual(
            owner?.windowLevel, UIWindow.Level.normal,
            """
            the presentation has to land at level .normal, the app's own; it \
            landed in \(landedIn). On this branch that means the key-window \
            preference reached an overlay UIKit owns: the firing screen would \
            mount over a system surface and isLaunchRootReady() would read the \
            #382 splash gate off somebody else's root
            """
        )

        detach(appWindow, systemWindow)
    }

    func testRootViewController_withNoScenes_reportsThatNoSceneIsAttached() {
        let located = ActiveWindowLocator.rootViewController(among: [])

        guard case let .failure(miss) = located else {
            return XCTFail("a process with no scenes has nothing to present on; it must not answer success")
        }
        XCTAssertEqual(
            miss, .noScene,
            """
            cold launch has to stay its own reason: a reader who greps this line \
            and sees «no window has a root» goes looking for rootless windows in \
            a process that has no windows at all
            """
        )
    }

    // MARK: - Hosting window: the three states behind the old single nil

    func testHostingWindow_prefersAWindowThatCanHostIt_overTheKeyWindowThatCannot() {
        let windows = [
            WindowCandidate(name: "app window", isKeyWindow: false, canHost: true),
            WindowCandidate(name: "keyboard", isKeyWindow: true, canHost: false)
        ]

        let located = ActiveWindowLocator.hostingWindow(
            among: windows, isKeyWindow: \.isKeyWindow, canHost: \.canHost
        )

        guard let picked = try? located.get() else {
            return XCTFail("a rootless key window must not turn a scene with a usable window into a miss")
        }
        XCTAssertEqual(
            picked.name, "app window",
            "the candidates are the windows that can host a presentation; «\(picked.name)» cannot"
        )
    }

    func testHostingWindow_withNoWindows_reportsAnEmptyScene() {
        let located = ActiveWindowLocator.hostingWindow(
            among: [WindowCandidate](), isKeyWindow: \.isKeyWindow, canHost: \.canHost
        )

        guard case let .failure(miss) = located else {
            return XCTFail("a scene without windows has nothing to present in")
        }
        XCTAssertEqual(
            miss, .noWindows,
            "«the scene has no windows» is fixed differently from «its windows have no roots»"
        )
    }

    func testHostingWindow_withNoWindowAbleToHostIt_reportsThatSeparately() {
        let windows = [
            WindowCandidate(name: "keyboard", isKeyWindow: true, canHost: false),
            WindowCandidate(name: "overlay", isKeyWindow: false, canHost: false)
        ]

        let located = ActiveWindowLocator.hostingWindow(
            among: windows, isKeyWindow: \.isKeyWindow, canHost: \.canHost
        )

        guard case let .failure(miss) = located else {
            return XCTFail("windows that cannot host a presentation are not a place to present")
        }
        XCTAssertEqual(
            miss, .noHostingWindow,
            "this is the state the single «no window scene» line used to hide behind two others"
        )
    }

    /// The three reasons exist so a log reader can fix by them. Byte-equal
    /// sentences would put the three states back into one grep, which is the
    /// finding, not the implementation.
    func testMiss_namesThreeDistinctStates() {
        let reasons = [
            ActiveWindowLocator.Miss.noScene.rawValue,
            ActiveWindowLocator.Miss.noWindows.rawValue,
            ActiveWindowLocator.Miss.noHostingWindow.rawValue
        ]

        XCTAssertEqual(
            Set(reasons).count, reasons.count,
            "two states sharing a sentence are one grep: \(reasons)"
        )
    }

    // MARK: - The fallbacks say when they fire

    func testHostingWindow_fallingBackToANonKeyWindow_leavesANotice() {
        let windows = [
            WindowCandidate(name: "app window", isKeyWindow: false, canHost: true),
            WindowCandidate(name: "keyboard", isKeyWindow: true, canHost: false)
        ]

        var lines: [(category: AppLogCategory, level: OSLogType, message: String)] = []
        _ = AppLogger.withTestSink({ lines.append(($0, $1, $2)) }, perform: {
            ActiveWindowLocator.hostingWindow(among: windows, isKeyWindow: \.isKeyWindow, canHost: \.canHost)
        })

        guard let notice = lines.first(where: { $0.message.contains("no key window that can host it") }) else {
            return XCTFail(
                """
                ALARM-752-ALERT-SHOWN reads the same whether the alert landed in \
                the key window or in an arbitrary one; without this line the \
                narrowing of #795 is unobservable. The sink saw \(lines.map(\.message))
                """
            )
        }
        XCTAssertEqual(
            notice.level, .default,
            "a backgrounded app genuinely has no key window — expected state, notice level, not error"
        )
    }

    func testHostingWindow_whenTheKeyWindowCanHostIt_saysNothing() {
        let windows = [
            WindowCandidate(name: "app window", isKeyWindow: true, canHost: true),
            WindowCandidate(name: "other", isKeyWindow: false, canHost: true)
        ]

        var lines: [String] = []
        _ = AppLogger.withTestSink({ lines.append($2) }, perform: {
            ActiveWindowLocator.hostingWindow(among: windows, isKeyWindow: \.isKeyWindow, canHost: \.canHost)
        })

        XCTAssertTrue(
            lines.isEmpty,
            "the ordinary case must stay silent, or the fallback line stops meaning anything: \(lines)"
        )
    }

    func testHostingScene_fallingBackToAnInactiveScene_leavesANotice() {
        let scenes = [
            SceneCandidate(name: "backgrounded", activationState: .background),
            SceneCandidate(name: "also backgrounded", activationState: .background)
        ]

        var lines: [(category: AppLogCategory, level: OSLogType, message: String)] = []
        _ = AppLogger.withTestSink({ lines.append(($0, $1, $2)) }, perform: {
            ActiveWindowLocator.hostingScene(among: scenes, activationState: \.activationState)
        })

        guard let notice = lines.first(where: { $0.message.contains("no foregroundActive scene") }) else {
            return XCTFail(
                """
                «presented in the active scene» and «there was no active scene, so \
                any of three» have to be distinguishable after the fact — that is \
                what #752/#795 were asked to answer. The sink saw \(lines.map(\.message))
                """
            )
        }
        XCTAssertTrue(
            notice.message.contains("\(scenes.count)"),
            "the line has to say how many scenes were on the table; it reads «\(notice.message)»"
        )
        XCTAssertEqual(notice.level, .default, "notification delivery from the background is not a failure")
    }

    func testHostingScene_withAnActiveScene_saysNothing() {
        let scenes = [
            SceneCandidate(name: "background", activationState: .background),
            SceneCandidate(name: "active", activationState: .foregroundActive)
        ]

        var lines: [String] = []
        _ = AppLogger.withTestSink({ lines.append($2) }, perform: {
            ActiveWindowLocator.hostingScene(among: scenes, activationState: \.activationState)
        })

        XCTAssertTrue(lines.isEmpty, "nothing fell back, so there is nothing to report: \(lines)")
    }

    func testHostingScene_withNoScenes_reportsThatNoSceneIsAttached() {
        let located = ActiveWindowLocator.hostingScene(
            among: [SceneCandidate](), activationState: \.activationState
        )

        guard case let .failure(miss) = located else {
            return XCTFail("no scene attached is the cold-launch race the callers defer on")
        }
        XCTAssertEqual(miss, .noScene, "the reason the caller logs has to be the one that happened")
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
