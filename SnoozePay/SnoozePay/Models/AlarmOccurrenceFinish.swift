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
    /// The moment the user first asked to finish this ring: the wake instant a
    /// confirmed finish records, however much later confirmation arrives.
    /// Absent in tickets persisted before it existed (decoded as `nil`); such
    /// a ticket can still be confirmed, but no wake is invented for it.
    let wakeAt: Date?

    init(id: UUID, alarmID: UUID, token: AlarmSnoozeToken?, wakeAt: Date? = nil) {
        self.id = id
        self.alarmID = alarmID
        self.token = token
        self.wakeAt = wakeAt
    }
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
