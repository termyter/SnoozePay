import os
import XCTest
@testable import SnoozePay

/// #859: a miss in `present(alarmID:snoozeCount:)` stops only the sound the
/// missing alarm owns, as `AppDelegate`'s miss does since #854.
///
/// Both miss branches, "not found" and "fetch failed", used to call
/// `stopAlarmSound()` unconditionally. Alarm A ringing on screen while the
/// pending slot held a request for a deleted alarm B: the slot flushed, the
/// presenter missed B, and A went silent with no dismiss.
///
/// Each test builds its own presenter over a repository on its own defaults
/// suite, so nothing here writes `.standard` or swaps a seam on the shared
/// presenter. No test loads a screen: A's ring is the service started under
/// A's id, as the presenter tests' `ring` does, and `tearDown` stops it.
@MainActor
final class AlarmFiringPresenterMissTests: XCTestCase {

    private typealias Line = (category: AppLogCategory, level: OSLogType, message: String)

    /// A sound id with no file behind it, so the service plays the synthetic
    /// tone: the bundle's files are not what this pins.
    private static let toneSoundID = "nonexistent_test_sound"

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var presenter: AlarmFiringPresenter!
    private var lines: [Line] = []

    /// What the presenter handed ``AlarmFiringPresenter/reportDataCorrupted``.
    /// Recorded instead of reaching the app delegate, so no data-corrupted
    /// alert mounts on the test host's window (#868).
    private var reported: [Error] = []

    override func setUp() {
        super.setUp()
        suiteName = "test.presenterMiss.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        let scheduler = AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: nil)
        presenter = AlarmFiringPresenter(alarmRepository: AlarmRepository(defaults: defaults, scheduler: scheduler))
        // A miss is terminal: it must never go looking for a host.
        presenter.locateHost = {
            XCTFail("a missing alarm reached the host lookup")
            return .failure(.noHostingWindow)
        }
        presenter.isRootReady = { true }
        presenter.reportDataCorrupted = { [weak self] in self?.reported.append($0) }
        AudioService.shared.stopAlarmSound()
        drainMainQueue()
    }

    override func tearDown() {
        AudioService.shared.stopAlarmSound()
        drainMainQueue()
        presenter = nil
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        lines = []
        reported = []
        super.tearDown()
    }

    /// The issue's scenario: B waits in the slot over the splash, A rings,
    /// and the flush that finds B deleted leaves A ringing.
    func testFlushForADeletedAlarm_leavesAnotherAlarmsSoundRinging() {
        let ringingID = UUID()
        let deletedID = UUID()
        presenter.isRootReady = { false }
        presenter.requestPresentation(alarmID: deletedID)
        XCTAssertEqual(presenter.pendingAlarmID, deletedID, "test precondition: B has to wait in the slot")
        ring(ringingID)

        presenter.isRootReady = { true }
        recording { presenter.flushPendingPresentation() }
        drainMainQueue()

        assertStillRinging(ringingID, "after the flush for the deleted alarm")
        XCTAssertNil(presenter.pendingAlarmID, "a miss is terminal: the deleted alarm must leave the slot")
        XCTAssertEqual(lines.map(\.message), [
            "firing-present: not found [alarm \(handle(deletedID)) at snooze 0]"
                + " — leaving the audio of \(handle(ringingID)) alone"
        ])
    }

    /// The stop the miss used to make for everyone is kept for the one case
    /// it was for: the missing alarm's own sound has no screen coming.
    func testMissForAnAlarmThatOwnsTheSound_stillStopsIt() {
        let missingID = UUID()
        ring(missingID)

        var answer = false
        recording { answer = presenter.present(alarmID: missingID, snoozeCount: 2) }

        XCTAssertTrue(answer, "a miss is terminal and must not be retried")
        XCTAssertNil(AudioService.shared.soundingAlarmID, "the missing alarm's own sound kept ringing with no screen")
        XCTAssertNil(AudioService.shared.currentAlarmID)
        XCTAssertEqual(lines.map(\.message), [
            "firing-present: not found [alarm \(handle(missingID)) at snooze 2] — stopping the audio it owns"
        ])
        XCTAssertTrue(reported.isEmpty, "a deleted alarm is not corrupted data; reported \(reported)")
    }

    /// The same gate on the other branch: the stored alarms fail to decode.
    func testFetchFailure_leavesAnotherAlarmsSoundRinging() {
        let missingID = UUID()
        corruptStoredAlarms(probing: missingID)
        let ringingID = UUID()
        ring(ringingID)

        var answer = false
        recording { answer = presenter.present(alarmID: missingID) }
        drainMainQueue()

        XCTAssertTrue(answer, "a miss is terminal and must not be retried")
        assertStillRinging(ringingID, "after a fetch failure for another alarm")
        XCTAssertEqual(lines.count, 1)
        let message = lines.first?.message ?? ""
        XCTAssertTrue(message.hasPrefix("firing-present: fetch failed ("), "wrong branch: «\(message)»")
        XCTAssertTrue(message.hasSuffix(
            "[alarm \(handle(missingID)) at snooze 0] — leaving the audio of \(handle(ringingID)) alone"
        ), "the line must name both alarms and the decision: «\(message)»")
    }

    func testFetchFailure_forAnAlarmThatOwnsTheSound_stillStopsIt() {
        let missingID = UUID()
        corruptStoredAlarms(probing: missingID)
        ring(missingID)

        recording { _ = presenter.present(alarmID: missingID) }

        XCTAssertNil(AudioService.shared.soundingAlarmID, "the missing alarm's own sound kept ringing with no screen")
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(
            lines.first?.message.hasSuffix("— stopping the audio it owns") == true,
            "«\(lines.first?.message ?? "")»"
        )
    }

    /// #868: an AlarmKit alarm whose stored alarms fail to decode used to end
    /// in one log line, with no screen and no alert. The miss now reports the
    /// corruption, once, with the decode error the alert spells its detail from.
    func testFetchFailure_reportsTheCorruptionOnce() {
        let missingID = UUID()
        corruptStoredAlarms(probing: missingID)

        recording { _ = presenter.present(alarmID: missingID) }
        drainMainQueue()

        XCTAssertEqual(reported.count, 1, "the user must be told the alarm data is corrupted")
        guard case .decodeFailure? = reported.first as? AlarmRepository.RepositoryError else {
            return XCTFail("the report must carry the decode error; got \(reported)")
        }
    }

    /// The same report when the request waited in the pending slot, the path
    /// an AlarmKit button takes on a cold launch: the flush misses, reports
    /// once, and the slot is emptied so no later flush reports again.
    func testFetchFailure_throughTheFlush_reportsOnceAndLeavesTheSlot() {
        let missingID = UUID()
        corruptStoredAlarms(probing: missingID)
        presenter.isRootReady = { false }
        presenter.requestPresentation(alarmID: missingID)
        XCTAssertTrue(reported.isEmpty, "nothing was fetched yet, so nothing may be reported")

        presenter.isRootReady = { true }
        recording {
            presenter.flushPendingPresentation()
            presenter.flushPendingPresentation()
        }
        drainMainQueue()

        XCTAssertEqual(reported.count, 1, "one miss, one report")
        XCTAssertNil(presenter.pendingAlarmID, "a miss is terminal: the corrupt alarm must leave the slot")
    }

    // MARK: - Helpers

    private func ring(_ alarmID: UUID) {
        AudioService.shared.startAlarmSound(soundID: Self.toneSoundID, alarmID: alarmID)
        XCTAssertEqual(AudioService.shared.currentAlarmID, alarmID, "test precondition: the alarm has to own the sound")
        XCTAssertEqual(AudioService.shared.state, .playing, "test precondition: the alarm has to be audible")
    }

    private func corruptStoredAlarms(probing alarmID: UUID) {
        defaults.set(Data("{ not a list of alarms".utf8), forKey: "stored_alarms")
        let probe = AlarmRepository(
            defaults: defaults, scheduler: AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: nil)
        )
        XCTAssertThrowsError(try probe.fetchChecked(id: alarmID), "test precondition: the fetch has to throw")
    }

    private func assertStillRinging(
        _ alarmID: UUID, _ context: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(
            AudioService.shared.currentAlarmID, alarmID,
            "\(context): the ringing alarm lost its sound", file: file, line: line
        )
        XCTAssertEqual(
            AudioService.shared.state, .playing,
            "\(context): the ringing alarm is not playing", file: file, line: line
        )
    }

    private func recording(_ body: () -> Void) {
        AppLogger.withTestSink({ self.lines.append(($0, $1, $2)) }, perform: body)
    }

    private func handle(_ alarmID: UUID) -> String { String(alarmID.uuidString.prefix(8)) }
}
