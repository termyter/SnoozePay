import XCTest
import os
@testable import SnoozePay

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
/// # What is not covered, and why it is named here
///
/// The guard refuses three states. Only the first — a presenter off the window
/// hierarchy — is driven below, because it is the one a test can put a
/// controller into and hold it there. The other two, `isBeingDismissed` and
/// `isBeingPresented`, are true only for the length of a transition UIKit is
/// running: sampling them means asserting *when* UIKit sets a flag, and a test
/// whose green depends on that is a flake waiting for a slower runner. They are
/// straight-line reads of UIKit's own state in a function whose other branch is
/// pinned, which is the trade taken here — not an oversight.
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
            AppDelegate.droppedAlertDiagnostic(presenting: host, message: message),
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
            AppDelegate.droppedAlertDiagnostic(presenting: offscreen, message: message),
            "the emitted line must BE the diagnostic, not merely carry its handle"
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
