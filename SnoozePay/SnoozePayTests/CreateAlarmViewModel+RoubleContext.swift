import Foundation
@testable import SnoozePay

/// Test-only shorthand for the editor view model in the rouble price context.
///
/// Production has no default for `priceContext:` (#1146), so a call site that
/// forgets the context does not compile. Tests written before tiers existed
/// describe the rouble editor; this keeps their expectations unchanged without
/// reading `BalanceService.shared.priceContext`, which on the host simulator
/// may hold a cached foreign scale.
extension CreateAlarmViewModel {
    convenience init(
        alarm: Alarm? = nil,
        repository: AlarmRepository = .shared,
        defaults: AlarmDefaults = .shared,
        balanceService: BalanceService = .shared,
        backendMonitor: AlarmBackendMonitor = AlarmBackendMonitor(),
        calendar: Calendar = .current,
        now: Date = Date()
    ) {
        self.init(
            alarm: alarm, repository: repository, defaults: defaults, balanceService: balanceService,
            backendMonitor: backendMonitor, priceContext: .scale(.rouble), calendar: calendar, now: now
        )
    }
}
