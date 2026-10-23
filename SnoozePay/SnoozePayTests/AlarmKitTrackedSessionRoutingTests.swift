import AlarmKit
import XCTest
@testable import SnoozePay

@MainActor
final class AlarmKitTrackedSessionRoutingTests: XCTestCase {
    private var fixture: TrackedSessionFixture!
    override func setUp() { super.setUp(); fixture = TrackedSessionFixture() }
    override func tearDown() { fixture.close(); fixture = nil; super.tearDown() }

    func testBothIntentPayloadsOpenFreshVMAtTheDurableCountWithoutFinishingOrCharging() async throws {
        let backend = TrackedSessionBackend()
        XCTAssertTrue(fixture.model(backend: backend).snooze())
        let token = try XCTUnwrap(backend.tokens.last)
        for isStop in [true, false] {
            let host = TrackedSessionHost()
            let presenter = fixture.presenter(host: host, backend: backend)
            presenter.isRootReady = { true }
            let router = router(presenter: presenter, backend: backend)
            var capturedStop: StopAlarmIntent?
            var capturedSnooze: SnoozeAlarmIntent?
            _ = try AlarmKitScheduler.makeSnoozeConfiguration(
                for: fixture.alarm, fireDate: try XCTUnwrap(backend.receipts.last).fireDate,
                token: token, attemptCount: 1,
                construct: { schedule, attributes, stop, snooze, sound in
                    capturedStop = stop
                    capturedSnooze = snooze
                    return .alarm(schedule: schedule, attributes: attributes,
                                  stopIntent: stop, secondaryIntent: snooze, sound: sound)
                }
            )
            var stop = try XCTUnwrap(capturedStop)
            var snooze = try XCTUnwrap(capturedSnooze)
            // Inject only the captured instances; actual perform() owns the routing call.
            stop.routerProvider = { router }
            snooze.routerProvider = { router }
            XCTAssertEqual(stop.sessionID, snooze.sessionID)
            XCTAssertEqual(stop.attemptID, snooze.attemptID)
            XCTAssertEqual(stop.sessionID, token.sessionID.uuidString)
            XCTAssertEqual(stop.attemptID, token.attemptID.uuidString)
            if isStop { _ = try await stop.perform() } else { _ = try await snooze.perform() }
            let mounted = try XCTUnwrap(host.screens.last)
            XCTAssertEqual(mounted.viewModel.snoozeCount, 1)
            XCTAssertEqual(mounted.viewModel.currentPenalty, 100)
            XCTAssertEqual(mounted.viewModel.nextRingDate(), backend.receipts.last?.fireDate)
            XCTAssertEqual(try fixture.store().resolve(token, alarmID: fixture.alarm.id).count, 1)
            XCTAssertTrue(presenter.pendingPresentations.isEmpty)
        }
        XCTAssertEqual(try fixture.ledger().fetchAllChecked().filter { $0.type == .charge }.count, 1)
    }

    func testColdRootQueueRetainsIdentityAndRevalidatesCountBeforeMount() throws {
        let backend = TrackedSessionBackend()
        XCTAssertTrue(fixture.model(backend: backend).snooze())
        let token = try XCTUnwrap(backend.tokens.last)
        let host = TrackedSessionHost()
        let presenter = fixture.presenter(host: host, backend: backend)
        presenter.isRootReady = { false }
        presenter.requestTrackedPresentation(alarmID: fixture.alarm.id, reference: .token(token))
        XCTAssertEqual(presenter.pendingPresentation?.snoozeReference, .token(token))
        XCTAssertTrue(host.screens.isEmpty)
        let next = fixture.model(backend: backend, reference: .token(token))
        XCTAssertTrue(next.snooze())
        presenter.isRootReady = { true }
        presenter.flushPendingPresentation()
        let mounted = try XCTUnwrap(host.screens.last)
        XCTAssertEqual(mounted.viewModel.snoozeCount, 2)
        XCTAssertEqual(mounted.viewModel.currentPenalty, 200)
        XCTAssertTrue(presenter.pendingPresentations.isEmpty)
    }

    func testFinishBeforeQueueFlushAndStaleIntentNeverMount() throws {
        let backend = TrackedSessionBackend()
        let model = fixture.model(backend: backend)
        XCTAssertTrue(model.snooze())
        let token = try XCTUnwrap(backend.tokens.last)
        let host = TrackedSessionHost()
        let presenter = fixture.presenter(host: host, backend: backend)
        presenter.isRootReady = { false }
        presenter.requestTrackedPresentation(alarmID: fixture.alarm.id, reference: .token(token))
        model.dismiss()
        presenter.isRootReady = { true }
        presenter.flushPendingPresentation()
        presenter.requestTrackedPresentation(alarmID: fixture.alarm.id, reference: .token(token))
        XCTAssertTrue(host.screens.isEmpty)
        XCTAssertTrue(presenter.pendingPresentations.isEmpty)
    }

    func testMalformedAndMissingTrackedPayloadCannotFallThroughToLegacyZero() throws {
        let backend = TrackedSessionBackend()
        let host = TrackedSessionHost()
        let presenter = fixture.presenter(host: host, backend: backend)
        presenter.isRootReady = { true }
        let router = router(presenter: presenter, backend: backend)
        router.handleStop(alarmIDString: fixture.alarm.id.uuidString, sessionIDString: "broken", attemptIDString: nil)
        let mounted = try XCTUnwrap(host.screens.last)
        XCTAssertFalse(mounted.viewModel.isProgressionAvailable)
        XCTAssertTrue(mounted.viewModel.currentPenalty.isNaN)
        XCTAssertFalse(mounted.viewModel.snooze())
        XCTAssertEqual(try fixture.ledger().fetchAllChecked().filter { $0.type == .charge }.count, 0)
    }

    func testObserverUsesExactConfirmedReceiptAndKeepsRawEpisodeDedup() throws {
        let backend = TrackedSessionBackend()
        XCTAssertTrue(fixture.model(backend: backend).snooze())
        let receipt = try XCTUnwrap(backend.receipts.last)
        let token = try XCTUnwrap(backend.tokens.last)
        var tracked: [AlarmSnoozeReference] = []
        var originals: [UUID] = []
        let observer = observer(originals: { originals.append($0) }, tracked: { _, reference in tracked.append(reference) })
        let snapshot = [AlarmSnoozeObservation(systemID: receipt.systemID, fixedFireDate: receipt.fireDate)]
        observer.handle(observations: snapshot)
        observer.handle(observations: snapshot)
        XCTAssertEqual(tracked, [.token(token)])
        XCTAssertTrue(originals.isEmpty)
        observer.handle(observations: [])
        observer.handle(observations: snapshot)
        XCTAssertEqual(tracked, [.token(token), .token(token)])
        observer.handle(observations: [])
        observer.handle(observations: [AlarmSnoozeObservation(
            systemID: receipt.systemID, fixedFireDate: receipt.fireDate.addingTimeInterval(1)
        )])
        XCTAssertEqual(tracked.last, .unavailable, "A different fixed schedule is not the latest stored session")
    }

    func testObserverPreservesDirectOriginalPrecedenceEvenWhenItHasAStoredSnoozeReceipt() throws {
        let backend = TrackedSessionBackend()
        XCTAssertTrue(fixture.model(backend: backend).snooze())
        let receipt = try XCTUnwrap(backend.receipts.last)
        let repository = AlarmRepository(defaults: fixture.defaults, scheduler: AlarmsListViewModelTests.StubScheduler())
        XCTAssertTrue(repository.save(Alarm(id: receipt.systemID, enabled: false)))
        var originals: [UUID] = []
        var tracked: [AlarmSnoozeReference] = []
        let observer = observer(originals: { originals.append($0) }, tracked: { _, reference in tracked.append(reference) })
        observer.handle(observations: [AlarmSnoozeObservation(systemID: receipt.systemID, fixedFireDate: receipt.fireDate)])
        XCTAssertEqual(originals, [receipt.systemID])
        XCTAssertTrue(tracked.isEmpty)
    }

    func testNewUnavailableCopyHasBothExactTranslations() throws {
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: project.appendingPathComponent("SnoozePay/Resources/Localizable.xcstrings"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(root["strings"] as? [String: Any])
        let entry = try XCTUnwrap(strings["firing.progression.unavailable"] as? [String: Any])
        let localizations = try XCTUnwrap(entry["localizations"] as? [String: [String: Any]])
        for (language, expected) in [
            "ru": "Не удалось проверить цену откладывания. Выключите будильник бесплатно.",
            "en": "Snooze price can’t be verified. Finish this alarm for free."
        ] {
            let unit = try XCTUnwrap(localizations[language]?["stringUnit"] as? [String: String])
            XCTAssertEqual(unit["value"], expected)
            XCTAssertEqual(unit["state"], "translated")
        }
    }

    private func router(presenter: AlarmFiringPresenter, backend: AlarmKitScheduling) -> AlarmKitActionRouter {
        let router = AlarmKitActionRouter()
        router.alarmRepository = AlarmRepository(defaults: fixture.defaults, scheduler: fixture.scheduler(backend))
        router.stopSystemAlarm = fixture.scheduler(backend).stopSystemAlarm
        router.present = { _ in XCTFail("Tracked payload lost its identity") }
        router.presentTracked = { presenter.requestTrackedPresentation(alarmID: $0, reference: $1) }
        return router
    }

    private func observer(
        originals: @escaping (UUID) -> Void,
        tracked: @escaping (UUID, AlarmSnoozeReference) -> Void
    ) -> AlarmKitAlertObserver {
        AlarmKitAlertObserver(
            stream: nil, onAlerting: originals,
            alarmRepository: AlarmRepository(defaults: fixture.defaults, scheduler: AlarmsListViewModelTests.StubScheduler()),
            snoozeSessions: fixture.store(), onTracked: tracked
        )
    }
}
