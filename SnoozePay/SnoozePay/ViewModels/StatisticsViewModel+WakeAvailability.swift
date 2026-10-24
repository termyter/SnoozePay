import Foundation

extension StatisticsViewModel {
    enum WakeTimeUnavailableReason: Equatable {
        case historyUnreadable
        case calculationUnavailable

        var message: String {
            switch self {
            case .historyUnreadable: return Localized.text("statistics.wake_time.unreadable")
            case .calculationUnavailable: return Localized.text("statistics.wake_time.calculation_unavailable")
            }
        }
    }

    enum WakeTimeAvailability: Equatable {
        case noRecentHistory
        case accumulating(WakeTimeStats)
        case available(WakeTimeStats)
        case unavailable(WakeTimeUnavailableReason)

        init(stats: WakeTimeStats) {
            if stats.medianWasRefused || stats.hasNothingToShow {
                self = .unavailable(.calculationUnavailable)
            } else if stats.medianMinutes != nil {
                self = .available(stats)
            } else if stats.recentSampleCount > 0 {
                self = .accumulating(stats)
            } else {
                self = .noRecentHistory
            }
        }

        var stats: WakeTimeStats? {
            switch self {
            case .available(let stats), .accumulating(let stats): return stats
            case .noRecentHistory, .unavailable: return nil
            }
        }
    }

    enum OverviewUnavailableReason: Equatable {
        case ledger(LedgerUnavailableReason)
        case wakeHistoryUnreadable
        case wakeTime(WakeTimeUnavailableReason)

        var message: String {
            switch self {
            case .ledger(let reason): return reason.message
            case .wakeHistoryUnreadable: return WakeTimeUnavailableReason.historyUnreadable.message
            case .wakeTime(let reason): return reason.message
            }
        }
    }

    var wakeDaysReadable: Bool { !wakeHistorySnapshot.days.isUnreadable }

    /// A time-only fault belongs in its card unless the normal empty-state
    /// early return would conceal it. Day-history faults invalidate the
    /// overview's clean-day/savings claims even when the ledger is healthy.
    var overviewUnavailableReason: OverviewUnavailableReason? {
        if let reason = ledgerUnavailableReason { return .ledger(reason) }
        if !wakeDaysReadable { return .wakeHistoryUnreadable }
        if charges.isEmpty, wakeDays.isEmpty, case .unavailable(let reason) = wakeTimeAvailability {
            return .wakeTime(reason)
        }
        return nil
    }
}
