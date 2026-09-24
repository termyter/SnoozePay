import os
import XCTest
@testable import SnoozePay

/// #835: what the one pending slot keeps, and which lines say so.
///
/// Since #834 the notification path parks in the slot too, so a request can
/// meet a record from the other source. By id alone, a lower count of the
/// same alarm replaced a higher one (#808's reset), and AlarmKit's
/// `requestPresentation` wrote over any record with no line at all. The swap
/// parked nothing until its completion ran, and it rebuilt a screen of the
/// same alarm that was already up and ringing, which brought back a screen
/// the user had stopped.
///
/// No test here loads a view: `dismissTapped` is called on a screen whose
/// view never loads, so no audio observer outlives the test (#846's teardown
/// lesson). Its Stop writes only to this suite's defaults.
@MainActor
final class AlarmFiringPresenterSlotTests: XCTestCase {

    private typealias Line = (category: AppLogCategory, level: OSLogType, message: String)

    /// A non-firing host that accepts what it is asked to present.
    private final class Host: UIViewController {
        private(set) var presentedScreens: [UIViewController] = []

        override func present(_ screen: UIViewController, animated flag: Bool, completion: (() -> Void)?) {
            presentedScreens.append(screen)
            (screen as? ReadBackFiringScreen)?.wiredPresenter = self
        }
    }

    private static let suite = "AlarmFiringPresenterSlotTests"
    private var top: UIViewController?
    private var rootReady = true
    private var dismissed: [UIViewController] = []
    /// Outstanding dismissal completions; none runs unless a test runs it.
    private var completions: [() -> Void] = []
    private var lines: [Line] = []
    private let defaults = UserDefaults(suiteName: suite) ?? .standard

    /// Spends earlier suites' main-queue backlog here, not in the first
    /// test's first turn, which paid 3.6 s of it (#618's pattern).
    override func setUp() {
        super.setUp()
        drainMainQueue()
    }

    override func tearDown() {
        AudioService.shared.stopAlarmSound()
        defaults.removePersistentDomain(forName: Self.suite)
        top = nil
        completions = []
        super.tearDown()
    }

    /// `confirmsDismissal == false` is UIKit dropping the dismissal: the
    /// screen never reads `isBeingDismissed`, the case the swap's park is for.
    private func makePresenter(alarms: [Alarm], confirmsDismissal: Bool = false) -> AlarmFiringPresenter {
        let byID = Dictionary(uniqueKeysWithValues: alarms.map { ($0.id, $0) })
        let presenter = AlarmFiringPresenter(alarmRepository: .shared)
        presenter.locateHost = { [self] in
            guard let top = self.top else { return .failure(.noHostingWindow) }
            return .success(top)
        }
        presenter.isRootReady = { [self] in self.rootReady }
        presenter.makeFiringScreen = { [self] in self.makeScreen($0, snoozeCount: $1) }
        presenter.mount = { [weak presenter] alarmID, count in
            guard let alarm = byID[alarmID] else { return false }
            return presenter?.present(alarm: alarm, snoozeCount: count) ?? false
        }
        presenter.dismissStaleScreen = { [self] screen, completion in
            self.dismissed.append(screen)
            let doubled = screen as? ReadBackFiringScreen
            if confirmsDismissal { doubled?.dismissalInFlight = true }
            self.completions.append {
                doubled?.dismissalInFlight = false
                completion()
            }
        }
        return presenter
    }

    /// A screen whose Stop touches nothing shared: wallet, ledger, alarm store
    /// and wake day live in this suite's defaults, and the scheduler has no
    /// system notifications. `alarmKit` picks the path: with it the system
    /// owns the sound, without it the screen does. `snoozedAt` is the last
    /// snooze tap; the ring on screen then started `snoozeMinutes` after it.
    private func makeScreen(
        _ alarm: Alarm, snoozeCount: Int = 0, alarmKit: Bool = false, startedAt: Date = Date(),
        snoozedAt: Date? = nil
    ) -> ReadBackFiringScreen {
        let scheduler = AlarmScheduler(
            notificationCenter: InertNotificationCenter(), alarmKit: alarmKit ? TestAlarmKitBackend() : nil
        )
        return ReadBackFiringScreen(viewModel: AlarmFiringViewModel(
            alarm: alarm, snoozeCount: snoozeCount, snoozeAnchor: snoozedAt,
            balanceService: BalanceService(defaults: defaults),
            alarmRepository: AlarmRepository(defaults: defaults, scheduler: scheduler),
            scheduler: scheduler,
            wakeStore: WakeEventStore(defaults: defaults),
            ledger: TransactionRepository(defaults: defaults, wakeStore: WakeEventStore(defaults: defaults)),
            firingStartedAt: startedAt
        ))
    }

    /// The notification path's sound, owned by `alarm`: what a ringing screen
    /// on that path has behind it.
    private func ring(_ alarm: Alarm) {
        AudioService.shared.startAlarmSound(soundID: "nonexistent_test_sound", alarmID: alarm.id)
        XCTAssertTrue(AudioService.shared.isPlaying, "test precondition: the alarm has to be audible")
    }

    private func finishDismissal() {
        XCTAssertFalse(completions.isEmpty, "test precondition: a dismissal has to be outstanding")
        guard !completions.isEmpty else { return }
        recording(completions.removeFirst())
    }

    private func runOneMainQueueTurn() {
        let turn = expectation(description: "one main-queue turn")
        DispatchQueue.main.async { turn.fulfill() }
        wait(for: [turn], timeout: 10)
    }

    private func recording(_ body: () -> Void) {
        AppLogger.withTestSink({ self.lines.append(($0, $1, $2)) }, perform: body)
    }

    private func handle(_ alarm: Alarm) -> String { String(alarm.id.uuidString.prefix(8)) }

    private func pending(_ alarm: Alarm, _ count: Int) -> AlarmFiringPresenter.PendingPresentation {
        AlarmFiringPresenter.PendingPresentation(alarmID: alarm.id, snoozeCount: count)
    }

    // MARK: - P1: id and count

    /// `(A, 3)` is parked over the splash; the same alarm then parks at 0, over
    /// the splash and on a host miss. Newest-wins by id alone left `(A, 0)`,
    /// and the retry priced the next snooze from the first step (#808).
    func testPark_forThisAlarmAtALowerCount_keepsTheHigherRecordAndSaysSo() throws {
        let alarm = Alarm()
        let presenter = makePresenter(alarms: [alarm])
        rootReady = false
        top = Host()
        XCTAssertFalse(presenter.present(alarm: alarm, snoozeCount: 3))
        XCTAssertEqual(presenter.pendingPresentation, pending(alarm, 3), "test precondition: (A, 3) is parked")

        recording { _ = presenter.present(alarm: alarm, snoozeCount: 0) }
        top = nil
        recording { _ = presenter.present(alarm: alarm, snoozeCount: 1) }

        XCTAssertEqual(presenter.pendingPresentation, pending(alarm, 3), "a lower count overwrote the parked (A, 3)")
        XCTAssertEqual(lines.count, 2, "\(lines.map(\.message))")
        for line in lines {
            XCTAssertTrue(line.message.contains("outranks it and stays"), "«\(line.message)»")
            XCTAssertTrue(line.message.contains("\(handle(alarm)) at snooze 3"), "«\(line.message)»")
            XCTAssertFalse(line.message.contains("dropped"), "nothing was lost: «\(line.message)»")
        }
        XCTAssertEqual(lines.first?.level, .default, "the splash park is a notice, and keeping a record adds no loss")
        XCTAssertEqual(lines.last?.level, .error, "the host miss keeps its own level: the alarm is still not up")
    }

    /// AlarmKit's request used to write over the slot: a notification-path
    /// record for another alarm went with no line (#835 addendum from #846).
    func testRequestPresentation_overAnotherAlarmsRecord_dropsItAndNamesBothAlarms() {
        let parked = Alarm()
        let requested = Alarm()
        let presenter = makePresenter(alarms: [parked, requested])
        rootReady = false
        top = Host()
        _ = presenter.present(alarm: parked, snoozeCount: 1)
        XCTAssertEqual(presenter.pendingPresentation, pending(parked, 1), "test precondition: another alarm is parked")

        recording { presenter.requestPresentation(alarmID: requested.id) }

        XCTAssertEqual(presenter.pendingPresentation, pending(requested, 0), "newest wins")
        let drops = lines.filter { $0.message.contains("another alarm's pending screen is dropped") }
        XCTAssertEqual(drops.count, 1, "the parked alarm went without a line: \(lines.map(\.message))")
        let line = drops.first
        XCTAssertEqual(line?.level, .error, "a lost alarm logged as a notice")
        XCTAssertTrue(line?.message.contains("\(handle(parked)) at snooze 1") ?? false, "«\(line?.message ?? "")»")
        XCTAssertTrue(line?.message.contains("\(handle(requested)) at snooze 0") ?? false, "«\(line?.message ?? "")»")
    }

    /// AlarmKit's requests always carry 0. Over a parked `(A, 2)` that reset
    /// the ladder; the record stays, and the flush mounts it at 2.
    func testRequestPresentation_forThisAlarmAtALowerCount_keepsTheHigherOneAndMountsIt() throws {
        let alarm = Alarm()
        let presenter = makePresenter(alarms: [alarm])
        rootReady = false
        top = Host()
        _ = presenter.present(alarm: alarm, snoozeCount: 2)

        recording { presenter.requestPresentation(alarmID: alarm.id) }

        XCTAssertEqual(presenter.pendingPresentation, pending(alarm, 2), "AlarmKit's 0 reset the parked count")
        let line = try XCTUnwrap(lines.first, "keeping the higher record left no line")
        XCTAssertEqual(line.level, .default)
        XCTAssertTrue(line.message.contains("outranks it and stays"), "«\(line.message)»")

        let root = Host()
        top = root
        rootReady = true
        presenter.flushPendingPresentation()
        let mounted = try XCTUnwrap(root.presentedScreens.first as? ReadBackFiringScreen, "the flush raised nothing")
        XCTAssertEqual(mounted.viewModel.snoozeCount, 2)
        XCTAssertNil(presenter.pendingPresentation)
    }

    // MARK: - P3: the swap parks before it dismisses

    /// UIKit drops the dismissal and never runs the completion. The request
    /// used to be parked only from that completion, so the notification path,
    /// which ignores `present`'s answer, lost it: neither shown nor parked.
    func testSwap_whenTheDismissalNeverReportsBack_leavesTheRequestParkedForTheNextFlush() {
        let alarm = Alarm()
        let presenter = makePresenter(alarms: [alarm])
        let stale = makeScreen(Alarm())
        top = stale

        recording { _ = presenter.present(alarm: alarm, snoozeCount: 2) }

        XCTAssertEqual(dismissed.count, 1, "test precondition: the swap ran")
        XCTAssertEqual(presenter.pendingPresentation, pending(alarm, 2), "the swap parked nothing before dismissing")
        let line = lines.first { $0.message.contains("swapping out") }
        XCTAssertEqual(line?.level, .default, "\(lines.map(\.message))")
        XCTAssertTrue(line?.message.contains("\(handle(alarm)) at snooze 2") ?? false, "«\(line?.message ?? "")»")

        presenter.flushPendingPresentation()

        XCTAssertEqual(dismissed.count, 2, "the next activation had nothing to retry")
        XCTAssertTrue(dismissed.last === stale)
    }

    /// Another alarm is parked when a swap B → A starts. Parking A over it
    /// would drop it, so the swap leaves it: A goes up, and the parked alarm
    /// is raised after, as on main. The line names B, whose sound stops with
    /// its screen.
    func testSwap_withAnotherAlarmParked_leavesItAndRaisesItAfterTheSwap() throws {
        let arriving = Alarm()
        let parked = Alarm()
        let ringing = Alarm()
        let presenter = makePresenter(alarms: [arriving, parked])
        rootReady = false
        presenter.requestPresentation(alarmID: parked.id)
        rootReady = true
        top = makeScreen(ringing)

        recording { _ = presenter.present(alarm: arriving) }

        XCTAssertEqual(presenter.pendingPresentation, pending(parked, 0), "the swap dropped the parked alarm")
        let line = try XCTUnwrap(lines.first { $0.message.contains("swapping out") }, "\(lines.map(\.message))")
        XCTAssertTrue(line.message.contains("screen of alarm \(handle(ringing))"), "B is not named: «\(line.message)»")
        XCTAssertFalse(lines.contains { $0.level == .error }, "nothing was lost: \(lines.map(\.message))")

        let host = Host()
        top = host
        finishDismissal()
        let arrivingScreen = try XCTUnwrap(host.presentedScreens.first as? ReadBackFiringScreen)
        XCTAssertEqual(arrivingScreen.viewModel.alarm.id, arriving.id)
        XCTAssertEqual(presenter.pendingPresentation, pending(parked, 0))
        top = arrivingScreen
        runOneMainQueueTurn()

        XCTAssertTrue(dismissed.last === arrivingScreen, "the parked alarm was never raised after the swap")
    }

    /// B's screen is going down for A's swap, and B asks again at its count.
    /// No second dismiss, and B waits in the slot. A leaves the slot, but its
    /// completion still puts it up, so the line must not call A dropped.
    func testReentry_forTheAlarmBeingSwappedOut_parksWithoutCallingTheSwapDropped() throws {
        let arriving = Alarm()
        let leaving = Alarm()
        let presenter = makePresenter(alarms: [arriving, leaving], confirmsDismissal: true)
        top = makeScreen(leaving, snoozeCount: 1)
        _ = presenter.present(alarm: arriving)
        XCTAssertEqual(presenter.pendingPresentation, pending(arriving, 0), "test precondition: the swap parked")

        var answer = true
        recording { answer = presenter.present(alarm: leaving, snoozeCount: 1) }

        XCTAssertFalse(answer)
        XCTAssertEqual(dismissed.count, 1, "the leaving screen was dismissed twice")
        XCTAssertEqual(presenter.pendingPresentation, pending(leaving, 1))
        let line = try XCTUnwrap(lines.first { $0.message.contains("still being dismissed") }, "\(lines.map(\.message))")
        XCTAssertEqual(line.level, .default, "«\(line.message)»")
        XCTAssertTrue(
            line.message.contains("\(handle(arriving)) at snooze 0 leaves the slot but is still being swapped in"),
            "«\(line.message)»"
        )
        XCTAssertFalse(line.message.contains("dropped"), "«\(line.message)»")
    }

    // MARK: - P4: this ring's screen already up

    /// The production case is EQUAL counts: a second trigger for the ring on
    /// screen carries the count the screen was built with. Through AlarmKit's
    /// request and the direct present, at 0 and at 2, on both paths. Every one
    /// swaps if `>=` is weakened to `>`.
    func testSettle_forThisRingAtTheSameCount_keepsTheScreenAndEmptiesTheSlot() {
        for alarmKit in [true, false] {
            for (count, viaRequest) in [(0, true), (0, false), (2, false)] {
                let label = "alarmKit=\(alarmKit) count=\(count) viaRequest=\(viaRequest)"
                dismissed = []
                lines = []
                let alarm = Alarm()
                let presenter = makePresenter(alarms: [alarm])
                top = makeScreen(alarm, snoozeCount: count, alarmKit: alarmKit)
                if !alarmKit { ring(alarm) }

                var answer = true
                recording {
                    if viaRequest {
                        presenter.requestPresentation(alarmID: alarm.id)
                    } else {
                        answer = presenter.present(alarm: alarm, snoozeCount: count)
                    }
                }

                XCTAssertTrue(dismissed.isEmpty, "\(label): this ring's screen was swapped for a copy")
                XCTAssertTrue(answer, label)
                XCTAssertNil(presenter.pendingPresentation, label)
                let settled = lines.first { $0.message.contains("up and ringing") }
                XCTAssertTrue(
                    settled?.message.contains("\(handle(alarm)) at snooze \(count)") ?? false,
                    "\(label): \(lines.map(\.message))"
                )
                AudioService.shared.stopAlarmSound()
            }
        }
    }

    /// Anything that does not prove "this ring, still ringing" takes the swap,
    /// as on main: a screen older than the window (yesterday's, with its
    /// billing window), one whose last re-ring is older than the window too,
    /// a notification-path screen with no sound or another alarm's, and a
    /// snoozed or stopped one, whose alarm's request is its next ring.
    func testSettle_onAScreenNotProvablyThisRing_swapsItAndSaysWhy() {
        let older = Date().addingTimeInterval(-AlarmFiringPresenter.currentFiringWindow - 60)
        let reasons: [String: AlarmFiringPresenter.RingMismatch] = [
            "older": .outsideWindow, "re-rang long ago": .outsideWindow, "silent": .silent,
            "other alarm's sound": .silent, "snoozed": .snoozed, "stopped": .stopped
        ]
        for (state, reason) in reasons {
            dismissed = []
            lines = []
            let alarm = Alarm()
            let presenter = makePresenter(alarms: [alarm])
            let onAlarmKit = state != "silent" && state != "other alarm's sound"
            // Re-rang long ago: snoozed a minute into the first ring, so the
            // re-ring started at `older`.
            let reRang = state == "re-rang long ago"
            let snoozedAt: Date? = reRang ? older.addingTimeInterval(-TimeInterval(alarm.snoozeMinutes * 60)) : nil
            var startedAt = state == "older" ? older : Date()
            if let snoozedAt { startedAt = snoozedAt.addingTimeInterval(-60) }
            let screen = makeScreen(
                alarm, snoozeCount: 1, alarmKit: onAlarmKit, startedAt: startedAt, snoozedAt: snoozedAt
            )
            switch state {
            case "other alarm's sound": ring(Alarm())
            case "snoozed": screen.isSnoozedStateActive = true
            case "stopped": screen.dismissTapped()
            default: break
            }
            top = screen

            var answer = true
            recording { answer = presenter.present(alarm: alarm, snoozeCount: 1) }

            XCTAssertFalse(answer, state)
            XCTAssertEqual(dismissed.count, 1, "\(state): answered with a screen that is not this ring's")
            XCTAssertEqual(presenter.pendingPresentation, pending(alarm, 1), state)
            let line = lines.first { $0.message.contains("swapping out") }
            XCTAssertTrue(line?.message.contains("(\(reason.rawValue))") ?? false, "\(state): \(lines.map(\.message))")
            AudioService.shared.stopAlarmSound()
        }
    }

    /// #855: mounted 20 minutes ago. On AlarmKit the window counts from the
    /// last re-ring (4 min ago, or 1 s ahead); with its own sound, the bound
    /// is `currentRingSoundingLimit`, so a 20-minute ring is not torn down.
    func testSettle_onTheCurrentRing_settlesWhenTheMountIsOutsideTheWindow() {
        let startedAt = Date().addingTimeInterval(-20 * 60)
        let snoozeLength: TimeInterval = 15 * 60
        let cases: [(String, Bool, Date?)] = [
            ("AlarmKit, re-rang 4 min ago", true, startedAt.addingTimeInterval(60)),
            ("AlarmKit, re-ring 1 s ahead", true, Date().addingTimeInterval(1 - snoozeLength)),
            ("notification path, ringing 20 min, never snoozed", false, nil)
        ]
        for (label, alarmKit, snoozedAt) in cases {
            dismissed = []
            lines = []
            let alarm = Alarm(snoozeMinutes: 15)
            let presenter = makePresenter(alarms: [alarm])
            top = makeScreen(alarm, snoozeCount: 1, alarmKit: alarmKit, startedAt: startedAt, snoozedAt: snoozedAt)
            if !alarmKit { ring(alarm) }

            var answer = false
            recording { answer = presenter.present(alarm: alarm, snoozeCount: 1) }

            XCTAssertTrue(dismissed.isEmpty, "\(label): the ring on screen was swapped for a copy")
            XCTAssertTrue(answer, label)
            XCTAssertNil(presenter.pendingPresentation, label)
            XCTAssertTrue(lines.contains { $0.message.contains("up and ringing") }, "\(label): \(lines.map(\.message))")
            AudioService.shared.stopAlarmSound()
        }
    }

    /// The new firing's sound is taken before `present`. An earlier firing's
    /// screen at count 3 must still be swapped past the limit, or the next
    /// snooze is charged at step 3; just inside it, a long ring settles.
    func testSettle_whileThisAlarmSounds_swapsAnEarlierFiringsScreen() {
        let limit = AlarmFiringPresenter.currentRingSoundingLimit
        let cases = [("2h59m", limit - 60, false), ("3h01m", limit + 60, true), ("a day", 86_400, true)]
        for (label, age, swaps) in cases {
            dismissed = []
            lines = []
            let alarm = Alarm()
            let presenter = makePresenter(alarms: [alarm])
            top = makeScreen(alarm, snoozeCount: 3, startedAt: Date().addingTimeInterval(-age))
            ring(alarm)

            var answer = swaps
            recording { answer = presenter.present(alarm: alarm, snoozeCount: 0) }

            XCTAssertEqual(answer, !swaps, label)
            XCTAssertEqual(dismissed.count, swaps ? 1 : 0, "\(label): \(lines.map(\.message))")
            if swaps {
                let line = lines.first { $0.message.contains("swapping out") }?.message ?? ""
                let reason = AlarmFiringPresenter.RingMismatch.previousFiring.rawValue
                XCTAssertTrue(line.contains("at snooze 3 (\(reason))"), "\(label): «\(line)»")
            }
            AudioService.shared.stopAlarmSound()
        }
    }

    // MARK: - The swap's completion finds this alarm up (#855)

    /// This alarm's screen Y went up during the swap's dismissal. Stale or
    /// silent, Y is swapped at the higher count (#808) through to a mounted
    /// screen; stopped or snoozed, the user answered the older request.
    func testCompletion_whenThisAlarmsScreenIsUpButNotRinging_swapsOnlyWhatTheUserDidNotAnswer() {
        let older = Date().addingTimeInterval(-AlarmFiringPresenter.currentFiringWindow - 60)
        /// `rebuilt`: the count the swap mounts at; `nil`, no swap.
        struct Case { let state: String, upCount: Int, requestCount: Int, rebuilt: Int? }
        let cases = [
            Case(state: "older", upCount: 1, requestCount: 1, rebuilt: 1),
            Case(state: "silent", upCount: 1, requestCount: 1, rebuilt: 1),
            Case(state: "older at a higher count", upCount: 2, requestCount: 0, rebuilt: 2),
            Case(state: "stopped", upCount: 1, requestCount: 1, rebuilt: nil),
            Case(state: "snoozed", upCount: 1, requestCount: 1, rebuilt: nil)
        ]
        for testCase in cases {
            let (state, upCount, requestCount) = (testCase.state, testCase.upCount, testCase.requestCount)
            dismissed = []
            completions = []
            lines = []
            let alarm = Alarm()
            let presenter = makePresenter(alarms: [alarm])
            top = makeScreen(Alarm())
            _ = presenter.present(alarm: alarm, snoozeCount: requestCount)
            XCTAssertEqual(dismissed.count, 1, "\(state): test precondition: the swap started")
            // AlarmKit unless silent, so each case fails one check only.
            let upAlready = makeScreen(
                alarm, snoozeCount: upCount, alarmKit: state != "silent",
                startedAt: state.hasPrefix("older") ? older : Date()
            )
            if state == "stopped" { upAlready.dismissTapped() }
            if state == "snoozed" { upAlready.isSnoozedStateActive = true }
            top = upAlready

            finishDismissal()
            runOneMainQueueTurn()

            guard let rebuiltCount = testCase.rebuilt else {
                XCTAssertNil(presenter.pendingPresentation, "\(state): the user's answer left the request parked")
                XCTAssertEqual(dismissed.count, 1, "\(state): the screen the user answered was swapped back in")
                XCTAssertTrue(lines.contains { $0.message.contains("already up and") }, "\(lines.map(\.message))")
                continue
            }
            let line = lines.first { $0.message.contains("swapping out") }?.message ?? ""
            XCTAssertTrue(line.contains("\(handle(alarm)) at snooze \(upCount) ("), "\(state): «\(line)»")
            XCTAssertTrue(dismissed.last === upAlready, "\(state): the screen up was never swapped for this ring's")
            let host = Host()
            top = host
            finishDismissal()
            let mounted = host.presentedScreens.last as? ReadBackFiringScreen
            XCTAssertEqual(mounted?.viewModel.snoozeCount, rebuiltCount, "\(state): none mounted, or stepped down")
            XCTAssertNil(presenter.pendingPresentation, state)
        }
    }

    // MARK: - Stop

    /// The ghost from #839's review: a record parked while the screen was up
    /// outlives Stop, and the next activation raises a firing screen for an
    /// alarm the user already stopped. Stop drops it.
    func testStop_dropsThisAlarmsParkedRecordSoNoScreenComesBack() throws {
        let alarm = Alarm()
        let presenter = makePresenter(alarms: [alarm])
        let host = Host()
        top = host
        XCTAssertTrue(presenter.present(alarm: alarm), "test precondition: the screen went up")
        let screen = try XCTUnwrap(host.presentedScreens.first as? ReadBackFiringScreen)
        rootReady = false
        presenter.requestPresentation(alarmID: alarm.id)
        XCTAssertEqual(presenter.pendingPresentation, pending(alarm, 0), "test precondition: a record is parked")

        recording { screen.dismissTapped() }

        XCTAssertNil(presenter.pendingPresentation, "Stop left the record parked")
        let line = try XCTUnwrap(lines.first { $0.message.contains("stopped on its screen") }, "\(lines.map(\.message))")
        XCTAssertTrue(line.message.contains(handle(alarm)), "«\(line.message)»")

        top = screen
        rootReady = true
        presenter.flushPendingPresentation()
        XCTAssertTrue(dismissed.isEmpty, "the stopped alarm's screen came back: \(dismissed)")
        XCTAssertEqual(host.presentedScreens.count, 1)
    }

    /// Stop drops only what its screen covers. Another alarm's record, or this
    /// alarm's at a higher count (a later ring), stays, and no line claims a
    /// drop.
    func testStop_leavesAnotherAlarmsRecordAndAHigherCount() throws {
        let alarm = Alarm()
        let other = Alarm()
        for (kept, label) in [(pending(other, 0), "another alarm"), (pending(alarm, 2), "a higher count")] {
            lines = []
            rootReady = true
            let presenter = makePresenter(alarms: [alarm, other])
            let host = Host()
            top = host
            XCTAssertTrue(presenter.present(alarm: alarm), "\(label): test precondition: the screen went up")
            let screen = try XCTUnwrap(host.presentedScreens.first as? ReadBackFiringScreen)
            rootReady = false
            presenter.requestPresentation(alarmID: kept.alarmID, snoozeCount: kept.snoozeCount)

            recording { screen.dismissTapped() }

            XCTAssertEqual(presenter.pendingPresentation, kept, "\(label): Stop dropped a record it does not cover")
            XCTAssertFalse(lines.contains { $0.message.contains("stopped on its screen") }, label)
        }
    }
}
