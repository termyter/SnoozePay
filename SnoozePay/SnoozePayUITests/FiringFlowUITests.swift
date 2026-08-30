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
/// This file holds BOTH halves of that tap: `FiringFlowUITests` below drives
/// the denied backend (in-place snoozed state), `AlarmKitSnoozeHandoffUITests`
/// the authorized one (the screen closes, #642). They share a file because
/// `SnoozePayUITests` is a plain `PBXGroup` — see that class's doc.
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

// MARK: - The authorized half of the same tap

/// End-to-end for the AUTHORIZED snooze — the path a normal user is on (#642).
///
/// With AlarmKit authorized the snooze re-fires as a REAL system alarm: the
/// scheduler stops the currently-alerting alarm and reschedules it, so the
/// in-app firing screen has nothing left to do and closes; the system owns the
/// next ring (#383). The in-place «отложено» countdown that `FiringFlowUITests`
/// above and `ProgressiveSnoozeUITests` assert is the OTHER branch — the one
/// for a backend that does not arm the next ring itself. Both of those pin
/// `-uitour-alarmkit denied` (#639), which left the branch every real user
/// takes with no E2E at all. This class is that branch.
///
/// Two things make it an assertion rather than a screenshot:
///
///   * `-uitour-alarmkit granted` pins the backend, because a simulator has no
///     way to grant AlarmKit authorization and an unpinned run would test
///     whatever the runtime happened to answer (`UITourAlarmKitBackend`, #606).
///   * `-uitour firing-presented` mounts the screen the way
///     `AlarmFiringPresenter` does — full-screen OVER the tab bar. The plain
///     `firing` route makes it the window ROOT, and `dismiss` on a view
///     controller nothing is presenting is a no-op, so on that route "the
///     screen closed" is not observable at all: the test would have passed
///     against an app that did nothing.
///
/// It lives in this file, next to the denied half it mirrors, for the reason
/// `dismissAppAlert` does: `SnoozePayUITests` is a plain `PBXGroup` in
/// `project.pbxproj` (not a synchronized folder like `SnoozePayTests`), so a
/// new .swift file there is not compiled until someone edits the project — a
/// PM-zone edit, and a silent no-op test until it happens.
final class AlarmKitSnoozeHandoffUITests: XCTestCase {

    /// Title of `firing.alert.snooze_not_scheduled` — the refusal raised on the
    /// DENIED path. Named here so this test can say "the authorized path raised
    /// the unauthorized path's alert" instead of timing out against a covered
    /// screen. Spelled as a literal for the reason given in `dismissAppAlert`.
    private static let refusalAlertTitle = "Откладывание не запланировано"

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        // Same reason as above (#438): don't leak a firing instance into the
        // next class's launch.
        XCUIApplication().terminate()
        super.tearDown()
    }

    func testAuthorizedSnoozeClosesFiringScreenInsteadOfSnoozingInPlace() {
        let app = XCUIApplication()
        // `-uitour-balance 1000` keeps the 50 ₽ snooze affordable, so the tap
        // reaches the scheduler instead of the no-balance layout.
        app.launchArguments = [
            "-uitour", "firing-presented", "-uitour-balance", "1000",
            "-uitour-alarmkit", "granted"
        ]
        app.launch()

        // 1. Firing screen up, presented over the tab bar.
        let snooze = app.buttons["firing.snoozeButton"]
        XCTAssertTrue(snooze.waitForExistence(timeout: 15),
                      "Firing snooze CTA should appear on the presented firing route")
        // The host is covered while the full-screen firing screen is up. Pinned
        // because step 3 measures against it: if the tab bar were reachable all
        // along, "the tab bar is back" would prove nothing.
        XCTAssertFalse(app.tabBars.firstMatch.exists,
                       "The full-screen firing screen should cover the tab bar it was presented over")

        let countdown = app.staticTexts["firing.countdown"]
        let refusal = app.alerts[Self.refusalAlertTitle]

        // 2. «Поспать ещё» → the screen closes, because the next ring became a
        // system alarm.
        //
        // Tapped in a bounded loop for the reason `dismissAppAlert` documents:
        // XCUITest drops synthesized touches outright (#523, #626, #647) — app
        // idle, element on screen, nothing happened. A dropped tap and a screen
        // that refuses to close look identical after one attempt, so we name
        // the two ways it is a real defect, then try once more; if the app is
        // genuinely stuck the second attempt fails too and the test goes red.
        var taps = 0
        var closed = false
        while taps < 2, !closed {
            snooze.tap()
            taps += 1
            closed = snooze.waitForNonExistence(timeout: 10)
            guard !closed else { break }

            XCTAssertFalse(
                refusal.exists,
                """
                The authorized path raised «\(Self.refusalAlertTitle)» — the alert that belongs \
                to a backend refusing to schedule. An authorized snooze must arm the next ring, \
                not explain why it won't
                """
            )
            XCTAssertFalse(
                countdown.exists,
                """
                The firing screen entered the in-place snoozed state (countdown to the next \
                ring). On an authorized backend the system owns that ring (#383): the screen \
                must close instead of counting down to an alarm it does not control
                """
            )
        }

        XCTAssertTrue(
            closed,
            "«Поспать ещё» on an authorized backend should close the firing screen (\(taps) tap(s))"
        )

        // 3. What is underneath is the app the user came from — the screen was
        // dismissed, not merely re-rendered without its CTA.
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5),
                      "Closing the firing screen should reveal the tab bar it was presented over")
        XCTAssertFalse(countdown.exists,
                       "The snoozed-state countdown must not be left behind after the hand-off")

        // 4. And nothing was swallowed into an alert on the way out. The
        // authorized path schedules cleanly, so ANY alert here — the refusal,
        // or the billed-and-refund-failed one (#197) — is a regression, and the
        // failure names which.
        let strayAlert = app.alerts.firstMatch
        if strayAlert.exists {
            XCTFail("An authorized snooze should raise no alert, but «\(strayAlert.label)» is up")
        }
    }
}

// MARK: - Alert handling shared by the E2E classes

/// Why every E2E class dismisses the app's own alerts by hand instead of
/// letting XCUITest do it — the mechanism behind #626.
///
/// When an alert covers the element a test is about to touch, XCUITest calls
/// it an *interrupting element* and runs the default interruption handler.
/// That handler taps a button **once**, waits for the app to go idle, then
/// gives itself a fixed 1.0 s for the alert to disappear. If the alert is
/// still there it does not tap again: it falls through to a last-ditch
/// predicate matching only English labels (`label CONTAINS[d] "Don’t" OR
/// label CONTAINS "Cancel"`), finds nothing in a Russian alert, logs
/// `unable to find any qualified button` and gives up **for the rest of the
/// test**. From that point every tap resolves to `Computed hit point
/// {-1, -1}` and every `waitForExistence` after it times out against a
/// covered screen.
///
/// The single tap is the whole problem. In both #626 failures the app was
/// *idle* when the check ran and the alert was still up — 2.3 s after the tap
/// in run 33295307930, 10 s after it in run 33295938983. That is not the app
/// being slow, that is the synthesized touch being dropped, the same failure
/// this suite already documents in `OnboardingFlowUITests` (#523). Which test
/// dies is decided by which one drew the dropped touch, which is exactly the
/// reported signature: different test each run, always on a
/// `waitForExistence` right after a tap.
///
/// So the cure is the one #523 landed on: re-tap while the state the app
/// controls has not changed, and fail loudly if it never does — instead of
/// one blind tap and a silent surrender that poisons every later step.
///
/// It lives in this file rather than its own because `SnoozePayUITests` is a
/// plain group in `project.pbxproj` — adding a file there is a PM-zone edit.
extension XCTestCase {

    /// Wait for the app-owned alert titled `expectedTitle` and dismiss it,
    /// re-tapping while it is still up. Returns `false` when that alert did
    /// not show up inside `timeout` — callers decide whether that is a failure
    /// or the normal case.
    ///
    /// Two separate defects are guarded here; they arrived from two directions
    /// and are easy to conflate.
    ///
    /// **1. The tap gets dropped, so tap again.** The synthesized touch is
    /// lost outright — in both #626 failures the app was *idle* and the alert
    /// was still up 2.3 s after the tap (run 33295307930) and 10 s after it
    /// (run 33295938983). That is not a slow runner; a slow runner was tested
    /// directly and did NOT reproduce it (proof branch A stalled the main
    /// thread on unfixed code and all seven E2E passed, twice). Same failure
    /// `OnboardingFlowUITests` already documents (#523), same cure: re-tap
    /// while the state the app owns has not changed, and fail loudly if it
    /// never does.
    ///
    /// Re-tapping cannot double-fire into the screen underneath: the loop
    /// re-checks that the alert is still on top before every tap, so a tap
    /// that landed ends it.
    ///
    /// **2. The title is REQUIRED, so we know WHAT we dismissed.** Matching
    /// «whatever alert is on screen» reads safe because every alert a tour
    /// launch can raise has a single «Ок» — but that is exactly what makes
    /// them indistinguishable. In particular `firing.alert.refund_failed` —
    /// billed, no re-fire, refund ALSO failed, the `AppLogger.ui.fault`
    /// wallet-desync case from #197 — is a single-«Ок» alert too. A regression
    /// turning every refused snooze into a wallet desync would have kept these
    /// tests green while the assertion message still claimed the refusal
    /// «explains itself».
    ///
    /// The title is spelled as a literal rather than read from `Localized`:
    /// XCUITest runs out of process and the app's string catalogue is not
    /// linked into this target. The duplication is deliberate — if someone
    /// changes the copy, this test should notice.
    ///
    /// Always button 0. Every alert a tour launch can raise is either
    /// single-action («Ок») or cancel-first («Отмена» then «Настройки»), and
    /// the second button of the latter leaves the app for Settings — so index
    /// 0 is the only safe choice.
    ///
    /// Deliberately NOT `@discardableResult`: a `false` here means «the alert
    /// never appeared», and a caller that drops it goes on to work against a
    /// screen that may still be covered — the exact failure #626 exists to
    /// kill. Callers must decide, in writing.
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

        var taps = 0
        while taps < 4, alert.exists {
            let button = alert.buttons.element(boundBy: 0)
            guard button.exists else { break }
            button.tap()
            taps += 1
            _ = alert.waitForNonExistence(timeout: 5)
        }

        XCTAssertFalse(
            alert.exists,
            "Alert «\(expectedTitle)» should be gone after \(taps) tap(s) on its first button"
        )
        return true
    }
}
