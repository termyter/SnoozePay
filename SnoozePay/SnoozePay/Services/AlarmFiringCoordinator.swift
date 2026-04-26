import Foundation

/// Handles the business logic triggered by notification actions on a fired
/// alarm (snooze charge + reschedule). Extracted from AppDelegate so the same
/// flow can be unit-tested without spinning up the UIApplication / notification
/// center machinery.
///
/// AppDelegate is responsible only for routing the raw `UNNotificationResponse`
/// into the right method here; all balance / repository / scheduler wiring
/// lives in this coordinator.
final class AlarmFiringCoordinator {

    static let shared = AlarmFiringCoordinator()

    // MARK: - Outcome

    /// Result of attempting a snooze from a notification action.
    /// Surfaced for tests and future telemetry — AppDelegate currently ignores
    /// the value because there's no UI affordance once the alarm screen is
    /// already dismissed.
    enum SnoozeOutcome: Equatable {
        /// Required identifiers (alarmID/snoozeCount) were missing or malformed.
        case invalidPayload
        /// Identifiers were valid but the alarm has been deleted from the repo.
        case alarmNotFound
        /// Balance was insufficient to cover the (possibly progressive) penalty.
        case insufficientFunds
        /// Charge succeeded and a new snooze notification was scheduled.
        case scheduled(newSnoozeCount: Int, charged: Double)
    }

    // MARK: - Dependencies

    private let alarmRepository: AlarmRepository
    private let balanceService: BalanceService
    private let scheduler: AlarmScheduler

    /// Production code MUST use `AlarmFiringCoordinator.shared`. Direct
    /// construction is intended for tests so they can inject mocks /
    /// isolated services without polluting the real singletons.
    #if DEBUG
    init(
        alarmRepository: AlarmRepository = .shared,
        balanceService: BalanceService = .shared,
        scheduler: AlarmScheduler = .shared
    ) {
        self.alarmRepository = alarmRepository
        self.balanceService = balanceService
        self.scheduler = scheduler
    }
    #else
    private init(
        alarmRepository: AlarmRepository = .shared,
        balanceService: BalanceService = .shared,
        scheduler: AlarmScheduler = .shared
    ) {
        self.alarmRepository = alarmRepository
        self.balanceService = balanceService
        self.scheduler = scheduler
    }
    #endif

    // MARK: - Snooze

    /// Resolves the alarm + snoozeCount from a notification's userInfo dict,
    /// charges the appropriate (possibly progressive) penalty, and schedules
    /// the next snooze notification. Returns a structured outcome so callers
    /// (and tests) can assert exactly what happened without scraping logs.
    @discardableResult
    func handleSnooze(userInfo: [AnyHashable: Any]) -> SnoozeOutcome {
        guard let payload = AlarmNotificationPayload(userInfo: userInfo) else {
            print("[AlarmFiringCoordinator] snooze: invalid payload \(userInfo)")
            return .invalidPayload
        }

        guard let alarm = alarmRepository.fetch(id: payload.alarmID) else {
            print("[AlarmFiringCoordinator] snooze: alarm \(payload.alarmID) not in repository")
            return .alarmNotFound
        }

        let newCount = payload.snoozeCount + 1
        let penalty = alarm.penalty(forSnoozeCount: newCount)

        let alarmID = payload.alarmID
        let charged = balanceService.charge(amount: penalty, alarmID: alarmID)
        guard charged else {
            print("[AlarmFiringCoordinator] snooze: insufficient funds for alarm \(alarmID), penalty=\(penalty)")
            return .insufficientFunds
        }

        scheduler.scheduleSnooze(for: alarm, snoozeCount: newCount)
        print("[AlarmFiringCoordinator] snooze: scheduled #\(newCount) for alarm \(alarmID), charged=\(penalty)")
        return .scheduled(newSnoozeCount: newCount, charged: penalty)
    }
}
