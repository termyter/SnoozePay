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
/// lesson).
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

    private var top: UIViewController?
    private var rootReady = true
    private var dismissed: [UIViewController] = []
    private var lines: [Line] = []
    private let defaults = UserDefaults(suiteName: "AlarmFiringPresenterSlotTests") ?? .standard

    override func tearDown() {
        AudioService.shared.stopAlarmSound()
        defaults.removePersistentDomain(forName: "AlarmFiringPresenterSlotTests")
        top = nil
        super.tearDown()
    }

    /// A dismissal here never reports back and never reads `isBeingDismissed`:
    /// UIKit dropping it, the case the swap's early park is for.
    private func makePresenter(alarms: [Alarm]) -> AlarmFiringPresenter {
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
        presenter.dismissStaleScreen = { [self] screen, _ in self.dismissed.append(screen) }
        return presenter
    }

    /// A screen whose Stop touches nothing shared: no AlarmKit, no system
    /// notifications, and its wake day goes to this suite's defaults.
    private func makeScreen(_ alarm: Alarm, snoozeCount: Int = 0) -> ReadBackFiringScreen {
        ReadBackFiringScreen(viewModel: AlarmFiringViewModel(
            alarm: alarm, snoozeCount: snoozeCount,
            scheduler: AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: nil),
            wakeStore: WakeEventStore(defaults: defaults)
        ))
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

    // MARK: - P4: this alarm's screen already up

    /// A record parked while this alarm's screen is up and ringing (a present
    /// UIKit deferred, a second trigger source). The flush used to swap the
    /// screen for a copy of itself, stopping its sound on the way down.
    func testFlush_whileThisAlarmsScreenIsUpAndRinging_clearsTheRecordInsteadOfSwapping() throws {
        let alarm = Alarm()
        let presenter = makePresenter(alarms: [alarm])
        rootReady = false
        presenter.requestPresentation(alarmID: alarm.id)
        XCTAssertEqual(presenter.pendingPresentation, pending(alarm, 0), "test precondition: the record is parked")
        top = makeScreen(alarm, snoozeCount: 1)
        rootReady = true

        recording { presenter.flushPendingPresentation() }

        XCTAssertTrue(dismissed.isEmpty, "this alarm's ringing screen was swapped for a copy: \(dismissed)")
        XCTAssertNil(presenter.pendingPresentation, "the record outlived the screen it asked for")
        let line = try XCTUnwrap(lines.first { $0.message.contains("up and ringing") }, "\(lines.map(\.message))")
        XCTAssertEqual(line.level, .default)
        XCTAssertTrue(line.message.contains("\(handle(alarm)) at snooze 1"), "«\(line.message)»")
    }

    /// The same alarm's screen, snoozed or stopped: a request for it is its
    /// next ring, and has to get a fresh screen, not the countdown or the
    /// morning summary left up.
    func testPresent_overThisAlarmsSnoozedOrStoppedScreen_stillSwaps() {
        for state in ["snoozed", "stopped"] {
            dismissed = []
            let alarm = Alarm()
            let presenter = makePresenter(alarms: [alarm])
            let screen = makeScreen(alarm, snoozeCount: 1)
            if state == "snoozed" { screen.isSnoozedStateActive = true } else { screen.dismissTapped() }
            top = screen

            XCTAssertFalse(presenter.present(alarm: alarm, snoozeCount: 1), state)

            XCTAssertEqual(dismissed.count, 1, "\(state): the next ring was answered with the old screen")
            XCTAssertEqual(presenter.pendingPresentation, pending(alarm, 1), state)
        }
    }

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
}
