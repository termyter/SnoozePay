import XCTest

/// End-to-end PoC for the core firing → snooze → wake loop.
///
/// Drives the REAL `AlarmFiringViewController` through the DEBUG `-uitour`
/// deep link (`UITourLauncher`), which mounts the firing screen directly as
/// the window root with a seeded balance — no onboarding / tab navigation to
/// tap through. The flow exercised here is the single most important path in
/// the product:
///
///   1. Firing screen up (snooze CTA + «Я встал» both present).
///   2. Tap «Поспать ещё» → the screen transitions IN PLACE into the snoozed
///      state with a live countdown (it deliberately does not dismiss, #226).
///   3. Tap «Я встал — выключить» → the WokeMorning summary is presented.
///   4. Tap «Закрыть» → the summary unwinds back to the firing screen.
///
/// This is intentionally ONE test: a stability probe. If it runs reliably and
/// green on CI, the e2e suite is worth expanding; if XCUITest proves flaky on
/// the CI simulator, we keep e2e thin and lean on unit tests. Selectors are
/// stable `accessibilityIdentifier`s, not localized button copy.
final class FiringFlowUITests: XCTestCase {

    /// Title of `firing.alert.snooze_not_scheduled` as the user sees it.
    /// Spelled here because XCUITest is out of process and cannot read the
    /// app's string catalogue; see `dismissAppAlert` for why the title must be
    /// named at all.
    private static let refusalAlertTitle = "Откладывание не запланировано"

    override func setUp() {
        super.setUp()
        // Fail fast: a missing element early means the later steps are
        // meaningless, and the first failure is the diagnostic that matters.
        continueAfterFailure = false
    }

    override func tearDown() {
        // Terminate the app under test so a leftover firing/snooze instance
        // can't survive into the next E2E class's launch() and make its
        // implicit terminate fail (#438).
        XCUIApplication().terminate()
        super.tearDown()
    }

    func testFiringSnoozeWakeFlow() {
        let app = XCUIApplication()
        // `-uitour firing` mounts AlarmFiringViewController as root;
        // `-uitour-balance 1000` guarantees the snooze is affordable so the
        // flow reaches the snoozed state rather than the no-balance layout.
        // `-uitour-alarmkit denied` states the backend this flow runs on
        // instead of inheriting whatever the simulator answers (#626): the
        // in-place snoozed state below exists only on a backend that does NOT
        // arm the next ring itself — on an authorized one the screen closes
        // and the system owns it (#383).
        app.launchArguments = [
            "-uitour", "firing", "-uitour-balance", "1000", "-uitour-alarmkit", "denied"
        ]
        app.launch()

        // 1. Firing screen — snooze CTA + «Я встал» dismiss are both present.
        let snooze = app.buttons["firing.snoozeButton"]
        let dismiss = app.buttons["firing.dismissButton"]
        XCTAssertTrue(snooze.waitForExistence(timeout: 10),
                      "Firing snooze CTA should appear on launch")
        XCTAssertTrue(dismiss.exists,
                      "«Я встал» dismiss button should be present on the firing screen")

        // 2. Snooze → the refusal is stated, then the snoozed state with a live
        // countdown appears in place. On the denied backend the schedule is
        // refused (#472) and the screen says so before anything else can be
        // tapped — clear that alert here, deliberately, rather than leaving it
        // to XCUITest (see `dismissAppAlert`).
        snooze.tap()
        XCTAssertTrue(
            dismissAppAlert(in: app, titled: Self.refusalAlertTitle, timeout: 10),
            "A snooze refused by an unauthorized backend should explain itself"
        )

        // ⚠️ This assertion pins behaviour that is KNOWN TO BE WRONG — see #641.
        // On a denied backend `scheduleSnooze` calls its completion
        // synchronously, so `exitSnoozedState()` runs before the state is
        // active (a no-op) and `enterSnoozedState()` then builds a countdown to
        // a ring that will never happen, behind an alert that just said it will
        // never happen. The countdown below IS that bug.
        //
        // It is asserted rather than inverted because it is what the app does
        // today, and a test that fails on unchanged code is worse than one that
        // documents the defect. When #641 is fixed, THIS TEST GOING RED IS
        // EXPECTED — it is not a sign the fix is wrong. Replace the assertion
        // with one on the active firing UI (or delete the snoozed-state tests
        // outright, if PM decides foreground snooze goes away with it).
        let countdown = app.staticTexts["firing.countdown"]
        XCTAssertTrue(countdown.waitForExistence(timeout: 5),
                      "Snoozed-state countdown should appear after «Поспать ещё» (see #641)")

        // 3. «Я встал — выключить» → the WokeMorning summary is presented.
        dismiss.tap()
        let wokeClose = app.buttons["woke.closeButton"]
        XCTAssertTrue(wokeClose.waitForExistence(timeout: 5),
                      "WokeMorning summary with «Закрыть» should appear after dismiss")

        // 4. «Закрыть» → the summary unwinds back to the firing screen.
        wokeClose.tap()
        XCTAssertTrue(snooze.waitForExistence(timeout: 5),
                      "Closing the summary should return to the firing screen")
        XCTAssertFalse(wokeClose.exists,
                       "WokeMorning summary should be gone after «Закрыть»")
    }
}

// MARK: - Alert handling shared by the E2E classes

/// Why every E2E class dismisses the app's own alerts by hand instead of
/// letting XCUITest do it — the mechanism behind #626.
///
/// When an alert covers the element a test is about to touch, XCUITest calls
/// it an *interrupting element* and runs the default interruption handler.
/// That handler taps a button, then waits a **fixed 1.0 s** for the alert to
/// go away. The window is not configurable, and missing it is not retried:
/// the handler falls through to a last-ditch predicate that matches only
/// English button labels (`label CONTAINS[d] "Don’t" OR label CONTAINS
/// "Cancel"`), finds nothing in a Russian alert, logs `unable to find any
/// qualified button` and gives up **for the rest of the test**. From that
/// point every tap resolves to `Computed hit point {-1, -1}` and every
/// `waitForExistence` after it times out against a covered screen.
///
/// On a loaded runner the round trip after the tap costs more than 1.0 s, so
/// which test dies is decided by which one drew the slow second — the exact
/// signature reported in #626 (two red runs in a row, a different test each
/// time, always on a `waitForExistence` right after a tap). Run 33295307930
/// missed the window by 1.01 s; the green run 33294965122 on the same code
/// made it with room to spare and confirmed handling.
///
/// Doing it here removes the coin flip: our own wait has a budget we choose,
/// and the assertion fails loudly if the alert will not go away, instead of
/// silently poisoning the remaining steps.
///
/// It lives in this file rather than its own because `SnoozePayUITests` is a
/// plain group in `project.pbxproj` — adding a file there is a PM-zone edit.
extension XCTestCase {

    /// Wait for the app-owned alert titled `expectedTitle` and dismiss it
    /// through its first button. Returns `false` when that alert did not show
    /// up inside `timeout` — callers decide whether that is a failure or the
    /// normal case.
    ///
    /// The title is REQUIRED, and that is the whole point of this helper
    /// (#639 gauntlet). Matching «whatever alert is on screen» reads safe
    /// because every alert a tour launch can raise has a single «Ок» — but
    /// that is exactly what makes them indistinguishable. In particular
    /// `firing.alert.refund_failed` — billed, no re-fire, refund ALSO failed,
    /// the `AppLogger.ui.fault` wallet-desync case from #197 — is a
    /// single-«Ок» alert too. A regression turning every refused snooze into a
    /// wallet desync would have kept these tests green while the assertion
    /// message still claimed the refusal «explains itself». Naming the title
    /// is what makes the assertion mean what it says.
    ///
    /// The title is spelled as a literal rather than read from `Localized`:
    /// XCUITest runs out of process and the app's string catalogue is not
    /// linked into this target. The duplication is deliberate — if someone
    /// changes the copy, this test should notice.
    ///
    /// Always button 0. Every alert a tour launch can raise is either
    /// single-action («Ок») or cancel-first («Отмена» then «Настройки»), and
    /// the second button of the latter leaves the app for Settings — so index
    /// 0 is the only safe choice. It is verified rather than trusted: the
    /// alert must be gone afterwards.
    ///
    /// Deliberately NOT `@discardableResult`: a `false` here means «the alert
    /// never appeared», and a caller that drops it goes on to work against a
    /// screen that may still be covered — the exact failure #626 was opened
    /// to kill. Callers must decide, in writing.
    func dismissAppAlert(
        in app: XCUIApplication,
        titled expectedTitle: String,
        timeout: TimeInterval
    ) -> Bool {
        let alert = app.alerts[expectedTitle]
        guard alert.waitForExistence(timeout: timeout) else {
            // Report what DID show up. «No alert titled X» sends the reader
            // hunting for a missing alert; «no alert titled X, but there was
            // one titled Y» hands them the actual regression.
            let other = app.alerts.firstMatch
            if other.exists {
                XCTFail("""
                    Expected the alert «\(expectedTitle)», \
                    but the screen showed «\(other.label)» instead
                    """)
            }
            return false
        }

        let button = alert.buttons.element(boundBy: 0)
        XCTAssertTrue(button.waitForExistence(timeout: 5),
                      "Alert «\(alert.label)» should offer a dismissing button")
        button.tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 10),
                      "Alert «\(alert.label)» should close after tapping «\(button.label)»")
        return true
    }
}
