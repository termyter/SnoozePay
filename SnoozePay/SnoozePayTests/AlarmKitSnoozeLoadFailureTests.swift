import os
import UserNotifications
import XCTest
@testable import SnoozePay

/// #868: the AlarmKit Snooze button on an alarm whose stored alarms fail to
/// decode. The router stops the system alarm and hands the id to the
/// presenter, which cannot load the alarm and raises no screen, so the paid
/// snooze used to become a Stop with nothing said. The router now posts the
/// snooze-failed banner itself.
///
/// Each test builds its own router over a repository on its own defaults
/// suite, so nothing here writes `.standard` (#814) or swaps a seam on the
/// shared router or presenter. `present` is recorded, never reaches the real
/// presenter, so no screen and no alert mounts on the test host.
@MainActor
final class AlarmKitSnoozeLoadFailureTests: XCTestCase {

    private typealias Line = (category: AppLogCategory, level: OSLogType, message: String)

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var router: AlarmKitActionRouter!
    private var poster: LocalNotificationPosterSpy!
    private var presented: [UUID] = []
    private var lines: [Line] = []

    override func setUp() {
        super.setUp()
        suiteName = "test.alarmKitSnoozeLoad.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        poster = LocalNotificationPosterSpy()
        router = AlarmKitActionRouter()
        router.alarmRepository = AlarmRepository(
            defaults: defaults,
            scheduler: AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: nil)
        )
        router.notificationPoster = poster
        router.present = { [weak self] in self?.presented.append($0) }
    }

    override func tearDown() {
        // `handleSnooze` stops the shared audio service; stop it again and
        // drain, so nothing it queued leaks into the next test (#846).
        AudioService.shared.stopAlarmSound()
        drainMainQueue()
        router = nil
        poster = nil
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        presented = []
        lines = []
        super.tearDown()
    }

    func testSnooze_whenStoredAlarmsFailToDecode_postsTheSnoozeFailedBanner() throws {
        defaults.set(Data("{ not a list of alarms".utf8), forKey: "stored_alarms")
        let alarmID = UUID()
        XCTAssertThrowsError(
            try router.alarmRepository.fetchChecked(id: alarmID),
            "test precondition: the stored alarms have to fail to decode"
        )

        snooze(alarmID)

        XCTAssertEqual(poster.requests.count, 1, "the user must be told the snooze was not scheduled")
        let banner = try XCTUnwrap(poster.requests.first)
        XCTAssertEqual(AppBannerNotification(identifier: banner.identifier), .snoozeScheduleFailed)
        XCTAssertEqual(banner.content.title, "Откладывание не запланировано")
        // The "refunded" copy: this button never charges, the screen does.
        XCTAssertTrue(banner.content.body.hasPrefix("Установите запасной — "), banner.content.body)
        XCTAssertEqual(banner.content.interruptionLevel, .timeSensitive)
        XCTAssertEqual(presented, [alarmID], "the presenter still runs: it raises the data-corrupted alert")

        let failures = lines.filter { $0.message.hasPrefix("ALARMKIT-868-SNOOZE-LOAD-FAILED: ") }
        XCTAssertEqual(failures.count, 1, "the lost snooze must leave one line with its error id: \(lines)")
        XCTAssertEqual(failures.first?.level, .error)
        XCTAssertTrue(
            failures.first?.message.contains("alarm \(alarmID.uuidString.prefix(8)) ") == true,
            "the line must name the alarm by its 8-digit handle: «\(failures.first?.message ?? "")»"
        )
    }

    /// Without notification permission the banner is refused too. That line
    /// names the same alarm as the load failure, so the two can be tied (#872).
    func testSnooze_whenTheBannerIsRefused_itsFailureLineNamesTheAlarm() {
        defaults.set(Data("{ not a list of alarms".utf8), forKey: "stored_alarms")
        poster.addError = NSError(domain: "UNErrorDomain", code: 1)
        let alarmID = UUID()

        snooze(alarmID)

        let refusals = lines.filter { $0.message.hasPrefix(AppDelegate.snoozeBannerPostFailedErrorID) }
        XCTAssertEqual(refusals.count, 1, "\(lines)")
        XCTAssertTrue(
            refusals.first?.message.contains("for alarm \(alarmID.uuidString.prefix(8)) ") == true,
            "«\(refusals.first?.message ?? "")»"
        )
    }

    /// A deleted alarm is not a lost snooze to report here: the presenter's
    /// "not found" branch owns it, and a banner blaming the schedule would lie.
    func testSnooze_whenTheAlarmIsMissing_postsNoBanner() {
        let alarmID = UUID()

        snooze(alarmID)

        XCTAssertTrue(poster.requests.isEmpty, "no load failed, yet a banner went out")
        XCTAssertEqual(presented, [alarmID])
        XCTAssertFalse(lines.contains { $0.message.hasPrefix("ALARMKIT-868-") }, "\(lines)")
    }

    // MARK: - Helpers

    /// `withTestSink` takes a synchronous body, and `handleSnooze` is `async`,
    /// so the body starts it in a task and waits for it: the wait turns the
    /// run loop with the sink still installed (the shape `withTestSink`'s own
    /// comment points at).
    private func snooze(_ alarmID: UUID) {
        let router: AlarmKitActionRouter = self.router
        let returned = expectation(description: "handleSnooze returned")
        AppLogger.withTestSink({ [weak self] in self?.lines.append(($0, $1, $2)) }, perform: {
            Task { @MainActor in
                await router.handleSnooze(alarmIDString: alarmID.uuidString)
                returned.fulfill()
            }
            wait(for: [returned], timeout: 5)
        })
    }
}
