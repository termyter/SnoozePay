import UIKit
import XCTest
@testable import SnoozePay

/// Controller entry/consumer tests. Presentation is captured; real modal
/// completion, native daemon timing and physical audibility remain device gates.
@MainActor
final class AlarmOccurrenceRecoveryEntryTests: XCTestCase {
    func testColdStartListOffersExactTrackedRetryEvenAfterTheAlarmRowWasDeleted() throws {
        let fixture = try OccurrenceVMFixture()
        defer { fixture.close() }
        let ticket = try fixture.recoveryTrackedTicket()
        XCTAssertTrue(fixture.seedRepository.delete(id: fixture.alarm.id))
        let center = NotificationCenter()
        let screen = makeList(fixture, recovery: fixture.recoveryService(), center: center)
        screen.loadViewIfNeeded()
        let table = try table(in: screen)
        let panel = try panel(in: table)
        XCTAssertFalse(table.isHidden, "The deleted alarm's durable action cannot hide behind the empty state")
        XCTAssertEqual(panel.retryButtons.count, 1)
        XCTAssertEqual(panel.retryButtons.first?.accessibilityIdentifier,
                       "alarmFinishRecovery.retry.\(ticket.id.uuidString)")
        XCTAssertTrue(fixture.wakes.wakeTimes().isEmpty)
        XCTAssertTrue(fixture.backend.occurrenceVerificationRequests.isEmpty)
        let owner = AudioService.shared.currentAlarmID
        let audio = AudioService.shared.state
        let queue = AlarmFiringPresenter.shared.pendingPresentations

        panel.retryButtons.first?.sendActions(for: .touchUpInside)

        XCTAssertNil(try fixture.store().pendingOccurrenceFinish(alarmID: fixture.alarm.id))
        XCTAssertEqual(fixture.backend.occurrenceVerificationRequests.count, 1)
        XCTAssertEqual(fixture.wakes.wakeDays().count, 1)
        XCTAssertTrue(screen.presentations.last is UIAlertController)
        XCTAssertFalse(screen.presentations.contains {
            $0 is AlarmFiringViewController || $0 is WokeMorningViewController
        })
        XCTAssertEqual(AudioService.shared.currentAlarmID, owner)
        XCTAssertEqual(AudioService.shared.state, audio)
        XCTAssertEqual(AlarmFiringPresenter.shared.pendingPresentations, queue)
        XCTAssertEqual(fixture.wallet.balance, 150)
        XCTAssertTrue(fixture.backend.cancelledIDs.isEmpty)
    }

    func testForegroundRefreshDiscoversDurableWorkWithoutAutomaticWakeOrNativeProbe() throws {
        let fixture = try OccurrenceVMFixture()
        defer { fixture.close() }
        let center = NotificationCenter()
        let screen = makeList(fixture, recovery: fixture.recoveryService(), center: center)
        screen.loadViewIfNeeded()
        let table = try table(in: screen)
        XCTAssertNil(table.tableHeaderView)
        let ticket = try fixture.recoveryTrackedTicket()
        let before = fixture.defaults.dictionaryRepresentation()

        center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        center.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        let panel = try panel(in: table)
        XCTAssertEqual(panel.retryButtons.count, 1)
        XCTAssertEqual(panel.retryButtons.first?.accessibilityIdentifier,
                       "alarmFinishRecovery.retry.\(ticket.id.uuidString)")
        XCTAssertEqual(fixture.defaults.dictionaryRepresentation() as NSDictionary, before as NSDictionary)
        XCTAssertTrue(fixture.backend.occurrenceVerificationRequests.isEmpty)
        XCTAssertTrue(fixture.wakes.wakeTimes().isEmpty)
    }

    func testQuietEntryComposesWithStreakAndRestoresTheOrdinaryHeaderAfterSuccess() throws {
        let fixture = try OccurrenceVMFixture()
        defer { fixture.close() }
        _ = try fixture.recoveryTrackedTicket()
        let screen = makeList(fixture, recovery: fixture.recoveryService(), center: NotificationCenter(), streak: 3)
        screen.loadViewIfNeeded()
        let table = try table(in: screen)
        let panel = try panel(in: table)
        let header = try XCTUnwrap(table.tableHeaderView)
        XCTAssertEqual(descendants(header).filter { $0 is AlarmsStreakBannerView }.count, 1)
        XCTAssertEqual(panel.retryButtons.count, 1)

        panel.retryButtons.first?.sendActions(for: .touchUpInside)

        XCTAssertTrue(table.tableHeaderView is AlarmsStreakBannerView)
        XCTAssertFalse(table.isHidden)
        XCTAssertFalse(descendants(try XCTUnwrap(table.tableHeaderView)).contains { $0 is AlarmFinishRecoveryPanel })
    }

    func testUnreadableDiscoveryShowsReloadInsteadOfPretendingNoPendingRequest() throws {
        let fixture = try OccurrenceVMFixture()
        defer { fixture.close() }
        let ticket = try fixture.recoveryTrackedTicket()
        let original = fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key)
        let corrupt = Data("unreadable-finish-metadata".utf8)
        fixture.defaults.set(corrupt, forKey: AlarmSnoozeSessionStore.key)
        let screen = makeList(fixture, recovery: fixture.recoveryService(), center: NotificationCenter())
        screen.loadViewIfNeeded()
        let table = try table(in: screen)
        let errorPanel = try panel(in: table)
        XCTAssertEqual(errorPanel.retryButtons.first?.accessibilityIdentifier, "alarmFinishRecovery.reload")
        XCTAssertTrue(descendants(errorPanel).compactMap { ($0 as? UILabel)?.text }.contains {
            $0.contains("Не удалось прочитать") || $0.contains("Could not read")
        })
        errorPanel.retryButtons.first?.sendActions(for: .touchUpInside)
        XCTAssertEqual(fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key), corrupt)
        XCTAssertTrue(fixture.backend.occurrenceVerificationRequests.isEmpty)

        fixture.defaults.set(original, forKey: AlarmSnoozeSessionStore.key)
        errorPanel.retryButtons.first?.sendActions(for: .touchUpInside)
        let recovered = try panel(in: table)
        XCTAssertEqual(recovered.retryButtons.first?.accessibilityIdentifier,
                       "alarmFinishRecovery.retry.\(ticket.id.uuidString)")
        XCTAssertTrue(fixture.wakes.wakeTimes().isEmpty)
    }

    func testNewFiringExposesPreviousTicketWithoutBorrowingTokenOrFinishingItsOwnScreen() throws {
        let fixture = try OccurrenceVMFixture()
        defer { fixture.close() }
        let ticket = try fixture.recoveryTrackedTicket()
        let screen = RecoveryFiringScreen(viewModel: fixture.model())
        screen.occurrenceRecovery = fixture.recoveryService()
        var stopped = 0
        screen.onUserStop = { stopped += 1 }
        let owner = AudioService.shared.currentAlarmID
        let audio = AudioService.shared.state
        let queue = AlarmFiringPresenter.shared.pendingPresentations

        screen.dismissTapped()

        XCTAssertNil(screen.viewModel.snoozeReference)
        XCTAssertEqual(screen.previousOccurrenceRecoveryEntry()?.ticket, ticket)
        let error = try XCTUnwrap(screen.presentations.last as? UIAlertController)
        XCTAssertTrue(error.actions.contains {
            ["Проверить предыдущую попытку", "Check Previous Finish"].contains($0.title ?? "")
        })
        fixture.backend.occurrenceVerificationResult = .failure(.nativeUnconfirmed)
        screen.retryPreviousOccurrence(ticket)
        XCTAssertEqual(try fixture.store().pendingOccurrenceFinish(alarmID: fixture.alarm.id), ticket)
        XCTAssertTrue(fixture.wakes.wakeTimes().isEmpty)
        XCTAssertFalse(screen.isStoppedByUser)
        XCTAssertEqual(stopped, 0)
        XCTAssertNil(screen.viewModel.snoozeReference)
        XCTAssertTrue(fixture.backend.occurrenceFinishRequests.isEmpty)
        XCTAssertTrue(fixture.backend.finishOriginalStopIDs.isEmpty)

        fixture.backend.occurrenceVerificationResult = .success(())
        screen.retryPreviousOccurrence(ticket)

        XCTAssertNil(try fixture.store().pendingOccurrenceFinish(alarmID: fixture.alarm.id))
        XCTAssertEqual(fixture.wakes.wakeDays().count, 1)
        XCTAssertFalse(screen.isStoppedByUser, "Quiet completion does not consume a new firing")
        XCTAssertEqual(stopped, 0)
        XCTAssertEqual(screen.dismissals, 0)
        XCTAssertNil(screen.viewModel.snoozeReference)
        XCTAssertFalse(screen.presentations.contains { $0 is WokeMorningViewController })
        XCTAssertEqual(AudioService.shared.currentAlarmID, owner)
        XCTAssertEqual(AudioService.shared.state, audio)
        XCTAssertEqual(AlarmFiringPresenter.shared.pendingPresentations, queue)
        XCTAssertTrue(fixture.backend.cancelledIDs.isEmpty)
        XCTAssertEqual(fixture.wallet.balance, 150)
    }

    func testMatchingTrackedFiringDoesNotOfferToReplaceItsOwnFinishWithRecovery() throws {
        let fixture = try OccurrenceVMFixture()
        defer { fixture.close() }
        let ticket = try fixture.recoveryTrackedTicket()
        let model = fixture.model()
        model.bindSnoozeSession(.token(try XCTUnwrap(ticket.token)), store: fixture.store())
        let screen = RecoveryFiringScreen(viewModel: model)
        screen.occurrenceRecovery = fixture.recoveryService()

        XCTAssertNil(screen.previousOccurrenceRecoveryEntry())
        XCTAssertEqual(model.snoozeReference, ticket.token.map(AlarmSnoozeReference.token))
        XCTAssertTrue(fixture.backend.occurrenceVerificationRequests.isEmpty)
    }

    func testStaleRecoveryAlertAndForeignTicketCannotDismissAnotherModalOrStartProof() throws {
        let fixture = try OccurrenceVMFixture()
        defer { fixture.close() }
        let ticket = try fixture.recoveryTrackedTicket()
        let recovery = fixture.recoveryService()
        let screen = RecoveryFiringScreen(viewModel: fixture.model())
        screen.occurrenceRecovery = recovery
        let stale = UIAlertController(title: "old retry", message: nil, preferredStyle: .alert)
        let foreign = UIAlertController(title: "another modal", message: nil, preferredStyle: .alert)
        screen.stubPresented = foreign
        let bytes = fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key)

        screen.retryPreviousOccurrence(ticket, from: stale)
        AlarmOccurrenceRecoveryAlerts.retry(ticket, from: stale, on: screen, recovery: recovery)

        XCTAssertTrue(screen.presentedViewController === foreign)
        XCTAssertTrue(screen.presentations.isEmpty)
        XCTAssertEqual(screen.dismissals, 0)
        XCTAssertTrue(fixture.backend.occurrenceVerificationRequests.isEmpty)
        XCTAssertEqual(fixture.defaults.data(forKey: AlarmSnoozeSessionStore.key), bytes)
        screen.stubPresented = nil
        let forged = AlarmOccurrenceFinishTicket(id: UUID(), alarmID: ticket.alarmID, token: ticket.token)
        screen.retryPreviousOccurrence(forged)
        XCTAssertTrue(screen.presentations.isEmpty)
        XCTAssertTrue(fixture.backend.occurrenceVerificationRequests.isEmpty)
        XCTAssertTrue(fixture.wakes.wakeTimes().isEmpty)
    }

    private func makeList(
        _ fixture: OccurrenceVMFixture, recovery: AlarmOccurrenceRecovering,
        center: NotificationCenter, streak: Int = 0
    ) -> RecoveryListScreen {
        let monitor = AlarmBackendMonitor(
            probe: AlarmsListBackendGuardTests.StubProbe(result: .available), notificationCenter: center
        )
        let model = AlarmsListViewModel(
            alarmRepository: fixture.repository, balanceService: fixture.wallet,
            transactionRepository: fixture.ledger, notificationCenter: center,
            alarmDefaults: AlarmDefaults(defaults: fixture.defaults), backendMonitor: monitor
        )
        model.loadData()
        return RecoveryListScreen(viewModel: model, bannerStreakCount: { streak },
                                  occurrenceRecovery: recovery, recoveryNotificationCenter: center)
    }

    private func table(in screen: UIViewController) throws -> UITableView {
        try XCTUnwrap(screen.view.subviews.compactMap { $0 as? UITableView }.first)
    }
    private func panel(in table: UITableView) throws -> AlarmFinishRecoveryPanel {
        let header = try XCTUnwrap(table.tableHeaderView)
        return try XCTUnwrap(descendants(header).compactMap { $0 as? AlarmFinishRecoveryPanel }.first)
    }
    private func descendants(_ view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap(descendants)
    }
}

@MainActor
private final class RecoveryListScreen: AlarmsListViewController {
    private(set) var presentations: [UIViewController] = []
    override func present(_ controller: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        presentations.append(controller)
        completion?()
    }
    override func presentStreakModalIfNeeded(in viewController: UIViewController? = nil) {}
}

@MainActor
private final class RecoveryFiringScreen: AlarmFiringViewController {
    private(set) var presentations: [UIViewController] = []
    private(set) var dismissals = 0
    var stubPresented: UIViewController?
    override var presentedViewController: UIViewController? { stubPresented }
    override func present(_ controller: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        presentations.append(controller)
        completion?()
    }
    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        dismissals += 1
        completion?()
    }
}
