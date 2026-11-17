import os
import XCTest
@testable import SnoozePay

@MainActor
final class AlarmFiringFinishDiagnosticTests: XCTestCase {
    private typealias LoggedLine = (category: AppLogCategory, level: OSLogType, message: String)
    private let prefix = "Snooze finish persistence failed: "
    private var fixture: TrackedSessionFixture!

    override func setUp() { super.setUp(); fixture = TrackedSessionFixture() }
    override func tearDown() { fixture.close(); fixture = nil; super.tearDown() }

    func testDismiss_invalidContextLogsTheFinishErrorAndContinuesCancellation() {
        let bytes = Data("{\"version\":2,\"sessions\":[]}".utf8)
        fixture.defaults.set(bytes, forKey: AlarmSnoozeSessionStore.key)
        let backend = TrackedSessionBackend()
        let model = fixture.model(backend: backend)
        var lines: [LoggedLine] = []

        AppLogger.withTestSink({ lines.append(($0, $1, $2)) }, perform: { model.dismiss() })

        let target = lines.filter { $0.category == .ui && $0.message.hasPrefix(prefix) }
        XCTAssertEqual(target.count, 1, "scheduler cleanup may log separately; the finish needs one UI diagnostic")
        XCTAssertEqual(target.first?.level, .error)
        XCTAssertEqual(target.first?.message, prefix + String(describing: AlarmSnoozeContextError.unavailable))
        XCTAssertEqual(fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key), bytes)
        XCTAssertTrue(backend.cancelled.contains(fixture.alarm.id), "a failed finish must not skip cancellation")
    }

    func testDismiss_validContextFinishesWithoutAFinishFailureDiagnostic() throws {
        let store = fixture.store()
        let token = try store.reserve(alarmID: fixture.alarm.id, sessionID: nil, expectedCount: 0)
        try store.recordCharge(token, alarmID: fixture.alarm.id)
        try store.complete(token, alarmID: fixture.alarm.id, receipt: nil)
        XCTAssertNoThrow(try store.resolve(token, alarmID: fixture.alarm.id), "precondition: session is unfinished")
        let model = fixture.model(backend: TrackedSessionBackend())
        var lines: [LoggedLine] = []

        AppLogger.withTestSink({ lines.append(($0, $1, $2)) }, perform: { model.dismiss() })

        XCTAssertFalse(lines.contains { $0.category == .ui && $0.message.hasPrefix(prefix) })
        XCTAssertThrowsError(try store.resolve(token, alarmID: fixture.alarm.id)) { error in
            guard case .finished? = error as? AlarmSnoozeContextError else {
                return XCTFail("Expected a finished session, got \(error)")
            }
        }
    }
}
