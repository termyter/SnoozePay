import XCTest
import os
@testable import SnoozePay

/// Answers `isBeingDismissed` with a constant so the branch that reads it can
/// be driven without staging a dismissal.
///
/// The property is an ObjC `readonly` on `open class UIViewController`, so
/// Swift lets a subclass override it — the same move
/// `PresentationDiagnosticsTests.StubPresenter` makes on
/// `presentedViewController`, and for the same reason: the alternative is a
/// live UIKit transition, whose flag timing would then be what is actually
/// under assertion.
private final class DismissingHost: UIViewController {
    override var isBeingDismissed: Bool { true }
}

/// The `isBeingPresented` half of the pair above.
private final class PresentingHost: UIViewController {
    override var isBeingPresented: Bool { true }
}

/// Returns from `present` having done nothing at all — no presentation, no
/// completion.
///
/// That is what UIKit does when it declines, and it is all the caller can see
/// of it: `present` came back and `presentedViewController` is not the alert.
/// Overriding is the only way to reach that state deliberately; the real
/// reasons live inside UIKit and none of them is inducible from a test.
private final class SwallowingHost: UIViewController {
    private(set) var wasAskedToPresent = false

    override func present(
        _ viewControllerToPresent: UIViewController,
        animated flag: Bool,
        completion: (() -> Void)? = nil
    ) {
        wasAskedToPresent = true
    }
}

/// The two alerts `AppDelegate` puts up itself: the corrupt-alarm-data one it
/// used to present without a trace, and the notifications-disabled one whose
/// copy used to live in Swift literals (#752).
///
/// # Why the corrupt-data half is driven through a static seam
///
/// `presentAlarmDataCorruptedAlert(error:)` finds its presenter through
/// `UIApplication.shared.connectedScenes`, which a unit test cannot stage —
/// there is one scene and it belongs to the test host. Everything this file is
/// about happens after that lookup, so the presentation moved into
/// `showAlarmDataCorruptedAlert(on:message:)`, which takes the presenter as an
/// argument. What stays uncovered is exactly the lookup: a `guard` that already
/// logs its own failure.
///
/// # Why both branches are read off the log seam
///
/// A dropped alert leaves nothing on screen by construction, so
/// `presentedViewController` cannot tell "the guard refused" from "UIKit tried
/// and failed" — the line is the only difference, and it is the whole remedy.
/// The shown branch is read the same way, and waits for the LINE rather than
/// for `presentedViewController`: UIKit sets that property inside `present`,
/// before the completion the line is written from, so a test built on it would
/// sample the sink too early and pass or fail on timing (#742).
///
/// # Why the two transition states are driven by subclass, not by transition
///
/// The first round of #752 left `isBeingDismissed` and `isBeingPresented`
/// untested, arguing that sampling them means asserting *when* UIKit sets a
/// flag, and that such a test flakes on a slower runner. That is true of an
/// end-to-end test staging a live transition — and `droppedAlertDiagnostic` is
/// not one: it is a pure function taking the controller as a parameter, which
/// is the entire reason it was split out. Both properties are ObjC `readonly`
/// on an `open` class, so a subclass answers them with a constant and the
/// branch becomes a straight-line read with nothing timed in it. The same trade
/// `PresentationDiagnosticsTests.StubPresenter` already takes, against the same
/// argument spelled out in the same words.
///
/// It mattered: with two of three branches unobserved, swapping the reasons or
/// making them identical left the suite green — in a function whose entire
/// output IS the reason.
///
/// # What is still not covered, and why it is named here
///
/// The presenter lookup in `presentAlarmDataCorruptedAlert(error:)` — a `guard`
/// on `UIApplication.shared.connectedScenes` that already logs its own failure
/// through the shared ``AppDelegate/droppedAlertLine(reason:message:)``. There
/// is one scene in this process and it belongs to the test host, so the failing
/// arm cannot be entered from here.
@MainActor
final class AppDelegateAlertTests: XCTestCase {

    /// Held for the test's lifetime — a released window takes the controller
    /// under assertion with it.
    private var window: UIWindow!
    /// Restored in `tearDown`: a suite that takes key status and never hands it
    /// back leaves every later presentation aimed at a window nobody is looking
    /// at (#728).
    private var previousKeyWindow: UIWindow?

    private let message = "Тестовое сообщение о повреждённых данных будильника"

    override func setUp() {
        super.setUp()
        // This suite spins the main run loop to wait for a presentation, so it
        // would otherwise spend the backlog the preceding synchronous tests
        // left queued inside its own wait (#618, #693).
        drainMainQueue()
        previousKeyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    }

    override func tearDown() {
        window?.rootViewController?.dismiss(animated: false)
        window?.rootViewController = nil
        window?.isHidden = true
        window = nil
        previousKeyWindow?.makeKeyAndVisible()
        previousKeyWindow = nil
        super.tearDown()
    }

    // MARK: - The corrupt-data alert reaches the user

    func testCorruptDataAlert_onAMountedPresenter_logsThatTheUserSawIt() {
        let host = makeMountedHost()
        XCTAssertNil(
            AppDelegate.droppedAlertDiagnostic(presenter: host, message: message),
            "test precondition: a mounted, settled presenter must not read as one that cannot present"
        )

        // Drained immediately before the sink goes in, not just in `setUp`: a
        // sink that waits catches whatever deferred work a neighbour left
        // behind, and a stray ALERT-SHOWN would carry the same handle this test
        // counts (#742).
        drainMainQueue()

        let shown = expectation(description: "the ALERT-SHOWN line reached the seam")
        var lines: [(category: AppLogCategory, level: OSLogType, message: String)] = []
        var fulfilled = false

        // `text` rather than `message`: the test's own `message` is what the
        // alert carries, and shadowing it inside the sink would make the two
        // assertions below read as if they compared a line against itself.
        AppLogger.withTestSink({ category, level, text in
            lines.append((category: category, level: level, message: text))
            // Guarded: a second fulfil is an XCTest API misuse failure.
            if !fulfilled, text.contains(AppDelegate.alertShownErrorID) {
                fulfilled = true
                shown.fulfill()
            }
        }, perform: {
            AppDelegate.showAlarmDataCorruptedAlert(on: host, message: message)

            // Read BEFORE the wait, and this is what makes the test able to
            // tell two implementations apart. Everything after the wait passes
            // just as well for a line emitted ahead of `present`: it lands in
            // the sink synchronously, fulfils the expectation, and `wait`
            // returns at once — and UIKit sets `presentedViewController` inside
            // `present` too, so even the on-screen check agrees. The whole
            // second half of #752's acceptance is "from the completion", so it
            // has to be asserted where the two differ, which is here.
            XCTAssertTrue(
                lines.allSatisfy { !$0.message.contains(AppDelegate.alertShownErrorID) },
                """
                ALERT-SHOWN must come from present's completion, not from before the call; \
                the sink already saw \(lines.map(\.message))
                """
            )
            // The other half of the same snapshot: the read-back after
            // `present` assumes UIKit assigns `presentedViewController`
            // synchronously, before the completion. If it did not, the drop
            // line would be sitting here — so a wrong assumption fails loudly
            // instead of shipping a DROPPED line for every alert the user did
            // in fact see.
            XCTAssertTrue(
                lines.allSatisfy { !$0.message.contains(AppDelegate.alertDroppedErrorID) },
                """
                the post-present read-back must see the alert UIKit just put up; \
                the sink saw \(lines.map(\.message))
                """
            )

            // 25 s to match the sibling presentation suites: on a saturated
            // three-core runner a tight deadline answers "the runner was busy"
            // instead of "it never logged".
            wait(for: [shown], timeout: 25)
        })

        let shownLines = lines.filter { $0.message.contains(AppDelegate.alertShownErrorID) }
        XCTAssertEqual(
            shownLines.count, 1,
            "one shown alert must leave exactly one line; the sink saw \(lines.map(\.message))"
        )
        XCTAssertEqual(shownLines.first?.category, .appDelegate, "the rest of this trail is filed there")
        XCTAssertEqual(shownLines.first?.level, .error, "an alarm the user lost is not a notice")
        XCTAssertTrue(
            shownLines.first?.message.contains(message) == true,
            "the line has to carry the sentence the user actually read; it reads «\(shownLines.first?.message ?? "")»"
        )
        XCTAssertTrue(
            lines.allSatisfy { !$0.message.contains(AppDelegate.alertDroppedErrorID) },
            "an alert that was shown must not also be reported as dropped"
        )

        let alert = host.presentedViewController as? UIAlertController
        XCTAssertNotNil(
            alert,
            """
            the line claims an alert was shown, so one has to be on screen. \
            \(presentationDiagnostics(rootedAt: window.rootViewController))
            """
        )
        XCTAssertEqual(alert?.message, message)
        XCTAssertEqual(alert?.actions.count, 1, "the alert only acknowledges; it decides nothing")
        XCTAssertEqual(
            alert?.actions.first?.title, Localized.text("common.button.ok"),
            "the acknowledge title comes from the catalogue"
        )
    }

    // MARK: - …and when it cannot, it says so

    /// The branch #752 exists for. Before it, a presenter that could not show
    /// the alert produced nothing at all: no alert, no line, and a user whose
    /// alarm went off with no explanation.
    ///
    /// The presenter here has a loaded view attached to no window — the state
    /// UIKit answers with "whose view is not in the window hierarchy" and then
    /// does nothing. So this asserts a record where UIKit leaves none; it does
    /// not take an alert away from anyone.
    func testCorruptDataAlert_onAnUnmountedPresenter_leavesTheLineInstead() {
        let offscreen = UIViewController()
        offscreen.loadViewIfNeeded()
        XCTAssertNil(
            offscreen.viewIfLoaded?.window,
            "test precondition: the presenter must be off the window hierarchy"
        )

        // No wait needed and none taken: this branch returns before `present`,
        // so the line lands inside the synchronous `perform`.
        var lines: [(category: AppLogCategory, level: OSLogType, message: String)] = []
        AppLogger.withTestSink({ lines.append((category: $0, level: $1, message: $2)) }, perform: {
            AppDelegate.showAlarmDataCorruptedAlert(on: offscreen, message: message)
        })

        let dropLines = lines.filter { $0.message.contains(AppDelegate.alertDroppedErrorID) }
        XCTAssertEqual(
            dropLines.count, 1,
            "a dropped alert must leave exactly one ALERT-DROPPED line; the sink saw \(lines.map(\.message))"
        )
        XCTAssertEqual(dropLines.first?.category, .appDelegate)
        XCTAssertEqual(dropLines.first?.level, .error, "a warning the user never saw is not a notice")
        XCTAssertNil(offscreen.presentedViewController, "the guard must not have presented anything")
        XCTAssertTrue(
            dropLines.first?.message.contains(message) == true,
            "the unshown message is the part worth recovering; it reads «\(dropLines.first?.message ?? "")»"
        )
        XCTAssertTrue(
            dropLines.first?.message.contains("UIViewController") == true,
            "the line must name what could not present; it reads «\(dropLines.first?.message ?? "")»"
        )

        // Ties the two halves together: without it,
        // `showAlarmDataCorruptedAlert` could emit a bare grep handle and every
        // assertion above would still pass, since they only look for substrings
        // this test wrote itself.
        XCTAssertEqual(
            dropLines.first?.message,
            AppDelegate.droppedAlertDiagnostic(presenter: offscreen, message: message),
            "the emitted line must BE the diagnostic, not merely carry its handle"
        )
    }

    /// The second of the guard's three refusals, and the first of the two the
    /// first round of #752 left unobserved.
    ///
    /// The presenter is mounted in the window, so the branch under assertion is
    /// reached rather than short-circuited by the window check ahead of it —
    /// and the reason is read by its words, because "the guard refused" is not
    /// the claim. The claim is that it refused for THIS reason: with the three
    /// reasons swapped, or made identical, a test that only counted lines stays
    /// green.
    func testCorruptDataAlert_onAPresenterBeingDismissed_saysWhichTransition() {
        let host = DismissingHost()
        attachToWindow(host)

        var lines: [(category: AppLogCategory, level: OSLogType, message: String)] = []
        AppLogger.withTestSink({ lines.append((category: $0, level: $1, message: $2)) }, perform: {
            AppDelegate.showAlarmDataCorruptedAlert(on: host, message: message)
        })

        let dropLines = lines.filter { $0.message.contains(AppDelegate.alertDroppedErrorID) }
        XCTAssertEqual(
            dropLines.count, 1,
            "a presenter mid-dismissal must leave one line; the sink saw \(lines.map(\.message))"
        )
        XCTAssertEqual(dropLines.first?.category, .appDelegate)
        XCTAssertEqual(dropLines.first?.level, .error)
        XCTAssertTrue(
            dropLines.first?.message.contains("DismissingHost is being dismissed") == true,
            """
            the line must name which transition swallowed the alarm, not merely that \
            something refused; it reads «\(dropLines.first?.message ?? "")»
            """
        )
        XCTAssertNil(host.presentedViewController, "the guard must not have presented anything")
    }

    /// The third refusal. Deliberately a separate case rather than a parameter
    /// of the one above: the two share everything except the words that tell a
    /// log reader which transition they are looking at, and those words are the
    /// only thing either test is really about.
    func testCorruptDataAlert_onAPresenterStillBeingPresented_saysWhichTransition() {
        let host = PresentingHost()
        attachToWindow(host)

        var lines: [(category: AppLogCategory, level: OSLogType, message: String)] = []
        AppLogger.withTestSink({ lines.append((category: $0, level: $1, message: $2)) }, perform: {
            AppDelegate.showAlarmDataCorruptedAlert(on: host, message: message)
        })

        let dropLines = lines.filter { $0.message.contains(AppDelegate.alertDroppedErrorID) }
        XCTAssertEqual(
            dropLines.count, 1,
            "a presenter mid-presentation must leave one line; the sink saw \(lines.map(\.message))"
        )
        XCTAssertTrue(
            dropLines.first?.message.contains("PresentingHost is itself still being presented") == true,
            """
            the line must name which transition swallowed the alarm, not merely that \
            something refused; it reads «\(dropLines.first?.message ?? "")»
            """
        )
        XCTAssertNil(host.presentedViewController, "the guard must not have presented anything")
    }

    // MARK: - …and when UIKit refuses for a reason the guard does not list

    /// The remainder #752 was closed without.
    ///
    /// The guard enumerates three states; UIKit declines for others it does not
    /// publish, and answers such a call by returning having done nothing and
    /// invoked no completion. Before the read-back after `present`, that
    /// produced no alert AND no line — the exact complaint the issue is about,
    /// left open for every reason outside the list.
    ///
    /// UIKit's own refusal is not stageable from a unit test: it happens inside
    /// `present` for reasons a test cannot induce. What the read-back actually
    /// reads IS stageable, and it is the whole of what a refusal looks like from
    /// the caller — `present` returned, and `presentedViewController` is not the
    /// alert. A presenter that swallows the call is that state exactly, and it
    /// keeps this test off UIKit's timing.
    func testCorruptDataAlert_whenThePresenterSwallowsTheCall_stillLeavesALine() {
        let host = SwallowingHost()
        attachToWindow(host)
        XCTAssertNil(
            AppDelegate.droppedAlertDiagnostic(presenter: host, message: message),
            "test precondition: the guard must PASS here, so the line can only come from the read-back"
        )

        var lines: [(category: AppLogCategory, level: OSLogType, message: String)] = []
        AppLogger.withTestSink({ lines.append((category: $0, level: $1, message: $2)) }, perform: {
            AppDelegate.showAlarmDataCorruptedAlert(on: host, message: message)
        })

        XCTAssertTrue(host.wasAskedToPresent, "test precondition: the call has to have reached `present`")
        let dropLines = lines.filter { $0.message.contains(AppDelegate.alertDroppedErrorID) }
        XCTAssertEqual(
            dropLines.count, 1,
            "a refusal the guard cannot name must still leave one line; the sink saw \(lines.map(\.message))"
        )
        XCTAssertEqual(dropLines.first?.category, .appDelegate)
        XCTAssertEqual(dropLines.first?.level, .error)
        XCTAssertTrue(
            dropLines.first?.message.contains(message) == true,
            "the unshown message is the part worth recovering; it reads «\(dropLines.first?.message ?? "")»"
        )
        XCTAssertTrue(
            dropLines.first?.message.contains("SwallowingHost did not put the alert up") == true,
            "the line must name who refused; it reads «\(dropLines.first?.message ?? "")»"
        )
        XCTAssertTrue(
            lines.allSatisfy { !$0.message.contains(AppDelegate.alertShownErrorID) },
            "nothing reached the screen, so nothing may claim it did"
        )
    }

    // MARK: - The notifications-disabled alert reads from the catalogue

    /// Three literals moved into `Localizable.xcstrings` by #752, pinned here by
    /// their words rather than by their keys.
    ///
    /// The title especially: `CreateAlarmUITests` matches this alert as
    /// `app.alerts["Уведомления выключены"]`, and the E2E job only runs behind
    /// the `ui-test` label — so without this, a reword would go red on some
    /// unrelated later PR rather than on the one that changed the words.
    func testNotificationsDisabledAlertCopyResolvesToTheShippedWords() {
        XCTAssertEqual(
            Localized.text("permissions.alert.notifications_disabled.title"),
            "Уведомления выключены",
            "CreateAlarmUITests matches this alert by these exact words"
        )
        XCTAssertEqual(
            Localized.text("permissions.alert.notifications_disabled.message"),
            "Без разрешения на уведомления будильники не сработают. Включите их в Настройках."
        )
        XCTAssertEqual(Localized.text("common.button.settings"), "Настройки")
        XCTAssertEqual(
            Localized.text("common.button.cancel"), "Отмена",
            "the alert's cancel action reuses the shared key rather than adding a second spelling"
        )
    }

    // MARK: - Helpers

    /// Puts `host`'s view in the window without making it the root.
    ///
    /// Enough for every test that never presents: the first branch of the guard
    /// reads `viewIfLoaded?.window`, and this is what fills it. Making a
    /// controller whose `isBeingDismissed` is a hardcoded `true` the ROOT of a
    /// key window would additionally hand that constant to UIKit's own
    /// bookkeeping, which is not a property worth discovering later.
    /// `PresentationDiagnosticsTests` attaches its stub chain the same way.
    private func attachToWindow(_ host: UIViewController) {
        window.addSubview(host.view)
        XCTAssertNotNil(
            host.viewIfLoaded?.window,
            "test precondition: the presenter must be IN the window hierarchy, or the first branch answers first"
        )
    }

    private func makeMountedHost() -> UIViewController {
        let host = UIViewController()
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.loadViewIfNeeded()
        XCTAssertNil(
            host.presentedViewController,
            "test precondition: mounting already presented something, and the assertions would grade it"
        )
        return host
    }
}
