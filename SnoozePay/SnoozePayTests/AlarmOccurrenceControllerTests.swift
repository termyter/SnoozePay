import UIKit
import XCTest
@testable import SnoozePay

@MainActor
final class AlarmOccurrenceControllerTests: XCTestCase {
    func testFailedFinishKeepsFiringAndErrorUntilConfirmedRetryShowsOneSummary() throws {
        let fixture = try OccurrenceVMFixture()
        defer { fixture.close() }
        fixture.backend.occurrenceFinishResult = .failure(.nativeUnconfirmed)
        let screen = FinishOutcomeScreen(viewModel: fixture.model())
        screen.loadViewIfNeeded()
        defer { screen.viewDidDisappear(false) }
        var stopped = 0
        screen.onUserStop = { stopped += 1 }

        screen.dismissTapped()

        XCTAssertFalse(screen.isStoppedByUser)
        XCTAssertEqual(stopped, 0)
        XCTAssertEqual(screen.dismissals, 0)
        XCTAssertTrue(fixture.wakes.wakeDays().isEmpty)
        XCTAssertTrue(screen.viewModel.finishRequested)
        XCTAssertFalse(screen.viewModel.snooze())
        XCTAssertTrue(screen.snoozeCTA?.isEnabled == false)
        XCTAssertEqual(screen.presentations.count, 1)
        let error = try XCTUnwrap(screen.presentations.first as? UIAlertController)
        XCTAssertTrue(["Завершение не подтверждено", "Finish not confirmed"].contains(error.title ?? ""))
        XCTAssertTrue([
            "Не удалось подтвердить выключение будильника. Попробуйте ещё раз. Платное откладывание пока недоступно.",
            "Could not confirm that the alarm stopped. Try again. Paid snoozing is temporarily unavailable."
        ].contains(error.message ?? ""))
        XCTAssertTrue(error.actions.contains { ["Повторить", "Try Again"].contains($0.title ?? "") })

        fixture.backend.occurrenceFinishResult = .success(())
        screen.dismissTapped()

        XCTAssertTrue(screen.isStoppedByUser)
        XCTAssertEqual(stopped, 1)
        XCTAssertTrue(screen.presentations.last is WokeMorningViewController)
        XCTAssertEqual(screen.presentations.count, 2)
        XCTAssertEqual(screen.dismissals, 0)
        XCTAssertEqual(fixture.wakes.wakeDays().count, 1)
        XCTAssertEqual(fixture.wallet.balance, 200)
    }

    func testDuplicateConfirmedFinishDoesNotPublishAnotherSummaryOrStopCallback() throws {
        let fixture = try OccurrenceVMFixture()
        defer { fixture.close() }
        let screen = FinishOutcomeScreen(viewModel: fixture.model())
        var stopped = 0
        screen.onUserStop = { stopped += 1 }

        screen.dismissTapped()
        screen.dismissTapped()

        XCTAssertTrue(screen.isStoppedByUser)
        XCTAssertEqual(stopped, 1)
        XCTAssertEqual(screen.presentations.count, 1)
        XCTAssertTrue(screen.presentations.first is WokeMorningViewController)
        XCTAssertEqual(fixture.backend.occurrenceFinishRequests.count, 1)
        XCTAssertEqual(screen.dismissals, 0)
        XCTAssertEqual(fixture.wakes.wakeDays().count, 1)
    }

    func testPendingTrackedSuccessCannotDismissTheErrorOrCancelWeeklyBeforeRetry() throws {
        let fixture = TrackedSessionFixture()
        defer { fixture.close() }
        let backend = TrackedSessionBackend()
        backend.schedule(fixture.alarm) { _ in }
        let original = backend.registrations[fixture.alarm.id]
        backend.deferred = true
        let screen = FinishOutcomeScreen(viewModel: fixture.model(backend: backend))
        let warnings = CriticalWarningCenter(defaults: fixture.defaults)
        warnings.isForegroundActive = { false }
        screen.criticalWarnings = warnings
        var stopped = 0
        screen.onUserStop = { stopped += 1 }

        screen.snoozeTapped()
        screen.dismissTapped()
        XCTAssertFalse(screen.isStoppedByUser)
        XCTAssertEqual(stopped, 0)
        XCTAssertTrue(screen.presentations.last is UIAlertController)
        XCTAssertTrue(WakeEventStore(defaults: fixture.defaults).wakeDays().isEmpty)
        backend.resolve()

        XCTAssertEqual(screen.dismissals, 0, "Late success cannot hand off an unconfirmed finish screen")
        XCTAssertTrue(screen.presentations.last is UIAlertController)
        XCTAssertFalse(screen.isStoppedByUser)
        XCTAssertNil(screen.viewModel.nextRingDate())
        XCTAssertTrue(backend.cancelled.isEmpty)
        XCTAssertEqual(backend.registrations[fixture.alarm.id], original)
        XCTAssertNil(backend.registrations[AlarmKitScheduler.snoozeID(for: fixture.alarm.id)])
        XCTAssertFalse(screen.viewModel.snooze())
        XCTAssertEqual(try fixture.ledger().fetchAllChecked().filter { $0.type == .charge }.count, 1)
        XCTAssertTrue(try fixture.ledger().fetchAllChecked().filter { $0.type == .refund }.isEmpty)

        screen.dismissTapped()
        XCTAssertTrue(screen.isStoppedByUser)
        XCTAssertEqual(stopped, 1)
        XCTAssertTrue(screen.presentations.last is WokeMorningViewController)
        XCTAssertEqual(backend.registrations[fixture.alarm.id], original)
        XCTAssertEqual(WakeEventStore(defaults: fixture.defaults).wakeDays().count, 1)
    }
}

@MainActor
private final class FinishOutcomeScreen: AlarmFiringViewController {
    private(set) var presentations: [UIViewController] = []
    private(set) var dismissals = 0

    override func present(_ controller: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        presentations.append(controller)
        completion?()
    }

    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        dismissals += 1
        completion?()
    }
}
