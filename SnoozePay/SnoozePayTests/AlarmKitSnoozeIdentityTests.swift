import XCTest
@testable import SnoozePay

#if canImport(AlarmKit)
@MainActor
final class AlarmKitSnoozeIdentityTests: XCTestCase {

    private var suite: String!
    private var defaults: UserDefaults!
    private var repository: AlarmRepository!

    override func setUp() {
        super.setUp()
        suite = "test.snoozeIdentity.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        repository = AlarmRepository(
            defaults: defaults, scheduler: AlarmsListViewModelTests.StubScheduler()
        )
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        repository = nil
        defaults = nil
        super.tearDown()
    }

    func testOriginalThenSnoozeResolveToTheSamePersistedAlarm() {
        let alarm = saveAlarm()
        var presented: [UUID] = []
        let observer = makeObserver { presented.append($0) }
        observer.handle(alertingIDs: [alarm.id])
        observer.handle(alertingIDs: [])
        let snoozeID = AlarmKitScheduler.snoozeID(for: alarm.id)
        XCTAssertNotEqual(snoozeID, alarm.id)
        observer.handle(alertingIDs: [snoozeID])
        observer.handle(alertingIDs: [snoozeID])
        XCTAssertEqual(presented, [alarm.id, alarm.id])
    }

    func testSnoozeCanPresentAgainAfterItsEpisodeEnds() {
        let alarm = saveAlarm()
        let snoozeID = AlarmKitScheduler.snoozeID(for: alarm.id)
        var presented: [UUID] = []
        let observer = makeObserver { presented.append($0) }
        observer.handle(alertingIDs: [snoozeID])
        observer.handle(alertingIDs: [])
        observer.handle(alertingIDs: [snoozeID])
        XCTAssertEqual(presented, [alarm.id, alarm.id])
    }

    func testIndependentOriginalAndSnoozeEachPresentOnce() {
        let alarmA = saveAlarm()
        let alarmB = saveAlarm()
        var presented: [UUID] = []
        let observer = makeObserver { presented.append($0) }
        let snapshot: Set<UUID> = [AlarmKitScheduler.snoozeID(for: alarmA.id), alarmB.id]
        observer.handle(alertingIDs: snapshot)
        observer.handle(alertingIDs: snapshot)
        XCTAssertEqual(presented.count, 2)
        XCTAssertEqual(Set(presented), [alarmA.id, alarmB.id])
    }

    func testKnownOriginalTakesPrecedenceOverTheInverseAlias() {
        let alarm = saveAlarm()
        let inverse = Alarm(id: AlarmKitScheduler.snoozeID(for: alarm.id), enabled: false)
        XCTAssertTrue(repository.save(inverse))
        var presented: [UUID] = []
        let observer = makeObserver { presented.append($0) }
        observer.handle(alertingIDs: [alarm.id])
        XCTAssertEqual(presented, [alarm.id])
    }

    func testUnknownIDStillReachesThePresentersMissingAlarmPath() {
        _ = saveAlarm()
        let unknown = UUID()
        var presented: [UUID] = []
        let observer = makeObserver { presented.append($0) }
        observer.handle(alertingIDs: [unknown])
        observer.handle(alertingIDs: [unknown])
        XCTAssertEqual(presented, [unknown])
    }

    func testCorruptStoreStillReachesThePresentersCheckedErrorPath() {
        let snoozeID = AlarmKitScheduler.snoozeID(for: saveAlarm().id)
        defaults.set(Data("not-json".utf8), forKey: "stored_alarms")
        var presented: [UUID] = []
        let observer = makeObserver { presented.append($0) }
        observer.handle(alertingIDs: [snoozeID])
        observer.handle(alertingIDs: [snoozeID])
        XCTAssertEqual(presented, [snoozeID], "Do not hide the presenter's corruption warning")
        XCTAssertThrowsError(try repository.fetchChecked(id: snoozeID))
    }

    private func saveAlarm() -> Alarm {
        let alarm = Alarm(enabled: false)
        XCTAssertTrue(repository.save(alarm))
        return alarm
    }

    private func makeObserver(onAlerting: @escaping @MainActor (UUID) -> Void) -> AlarmKitAlertObserver {
        AlarmKitAlertObserver(stream: nil, onAlerting: onAlerting, alarmRepository: repository)
    }
}
#endif
