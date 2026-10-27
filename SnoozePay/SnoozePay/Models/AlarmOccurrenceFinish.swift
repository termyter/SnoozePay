import Foundation

enum AlarmOccurrenceFinishError: Error, Equatable {
    case unsupported, busy, ownershipUnavailable, sessionUnavailable
    case inventoryUnavailable, nativeUnconfirmed, persistenceFailed
}

enum AlarmOccurrenceFinishOutcome: Equatable {
    case completedNow, alreadyCompleted
}

struct AlarmOccurrenceFinishTicket: Codable, Equatable {
    let id: UUID
    let alarmID: UUID
    let token: AlarmSnoozeToken?
}

/// A projection of a fresh complete native inventory, never the alerting-only stream.
nonisolated struct NativeOccurrenceSnapshot: Equatable, Sendable {
    enum Phase: Equatable, Sendable { case scheduled, countdown, paused, alerting, unknown }

    struct Weekly: Equatable, Sendable {
        let hour: Int
        let minute: Int
        let mondayFirstDays: Set<Int>
    }

    let id: UUID
    let phase: Phase
    let weekly: Weekly?
    var fixedDate: Date?
}

/// Derived cleanup is allowed only after the caller established exclusive ownership.
nonisolated struct AlarmOccurrenceFinishRequest: Equatable, Sendable {
    let alarmID: UUID
    let weekly: NativeOccurrenceSnapshot.Weekly?
    let expectedDerivedFireDate: Date?
    let allowsUntrackedDerived: Bool
}
