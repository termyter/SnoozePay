import Foundation
import os

struct AlarmOccurrenceRecoveryEntry: Equatable {
    let ticket: AlarmOccurrenceFinishTicket
    let alarmName: String?

    /// A new original route must not borrow the previous attempt's token.
    func differs(from reference: AlarmSnoozeReference?) -> Bool {
        guard let token = ticket.token else { return false }
        return reference != .token(token)
    }
}

@MainActor
protocol AlarmOccurrenceRecovering: AnyObject {
    func pendingFinishes() throws -> [AlarmOccurrenceRecoveryEntry]
    func resume(
        _ ticket: AlarmOccurrenceFinishTicket
    ) -> Result<AlarmOccurrenceFinishOutcome, AlarmOccurrenceFinishError>
}

@MainActor
protocol AlarmOccurrenceRecoveryVerifying: AnyObject {
    func verifyPendingOccurrenceFinish(
        currentAlarm: Alarm?, ticket: AlarmOccurrenceFinishTicket
    ) -> Result<Void, AlarmOccurrenceFinishError>
}

extension AlarmScheduler: AlarmOccurrenceRecoveryVerifying {}

/// Explicit recovery of an existing local operation. It never mounts a firing
/// screen, claims audio/queue ownership, or changes the native alarm inventory.
@MainActor
final class AlarmOccurrenceRecovery: AlarmOccurrenceRecovering {
    static let shared = AlarmOccurrenceRecovery(
        repository: .shared, scheduler: AlarmScheduler.shared, sessions: .shared, wakes: .shared
    )

    private let repository: AlarmRepository
    private let scheduler: AlarmOccurrenceRecoveryVerifying
    private let sessions: AlarmSnoozeSessionStore
    private let wakes: WakeEventStore
    private let calendar: Calendar?
    private var completed: [UUID: AlarmOccurrenceFinishTicket] = [:]

    init(
        repository: AlarmRepository, scheduler: AlarmOccurrenceRecoveryVerifying,
        sessions: AlarmSnoozeSessionStore, wakes: WakeEventStore, calendar: Calendar? = nil
    ) {
        self.repository = repository
        self.scheduler = scheduler
        self.sessions = sessions
        self.wakes = wakes
        self.calendar = calendar
    }

    /// Discovery is a checked read, including requests whose alarm was deleted.
    /// It does not prove native completion, record a wake or rewrite old bytes.
    func pendingFinishes() throws -> [AlarmOccurrenceRecoveryEntry] {
        let tickets = try sessions.pendingOccurrenceFinishes()
        guard !tickets.isEmpty else { return [] }
        let alarms = try repository.fetchOccurrenceFinishAlarms()
        return tickets.map { ticket in
            let name = alarms.first { $0.id == ticket.alarmID }?.name
            return AlarmOccurrenceRecoveryEntry(ticket: ticket, alarmName: name)
        }
    }

    func resume(
        _ ticket: AlarmOccurrenceFinishTicket
    ) -> Result<AlarmOccurrenceFinishOutcome, AlarmOccurrenceFinishError> {
        if let previous = completed[ticket.id] {
            return previous == ticket ? .success(.alreadyCompleted) : .failure(.ownershipUnavailable)
        }
        do {
            guard try sessions.pendingOccurrenceFinish(alarmID: ticket.alarmID) == ticket else {
                return .failure(.ownershipUnavailable)
            }
            _ = try sessions.validateOccurrenceFinish(ticket)
            var current = try currentAlarm(for: ticket)
            switch scheduler.verifyPendingOccurrenceFinish(currentAlarm: current, ticket: ticket) {
            case .failure(let error): return .failure(error)
            case .success: break
            }
            // An injected reader can expose a concurrent edit; never persist
            // the captured model over a newer record after native proof.
            guard try currentAlarm(for: ticket) == current else {
                return .failure(.ownershipUnavailable)
            }
            if let alarm = current, alarm.enabled, alarm.repeatMode == .never || alarm.repeatDays.isEmpty {
                try repository.persistFinishedOneShot(alarm)
                current = alarm.with(enabled: false)
            }
            guard try currentAlarm(for: ticket) == current else {
                return .failure(.persistenceFailed)
            }
            try sessions.commitOccurrenceFinish(ticket)
            completed[ticket.id] = ticket
            // The wake belongs to the ring the user finished, not to this
            // confirmation, which can land in the evening or on a later day.
            // A ticket persisted before `wakeAt` existed has no instant to
            // reconstruct; skipping beats writing a wrong day row and instant.
            if let wakeAt = ticket.wakeAt {
                wakes.recordWake(on: wakeAt, calendar: calendar ?? .current)
            } else {
                AppLogger.emit(.ui, .default, "Recovered finish has no wake instant; wake not recorded")
            }
            return .success(.completedNow)
        } catch let error as AlarmOccurrenceFinishError {
            return .failure(error)
        } catch {
            return .failure(.persistenceFailed)
        }
    }

    private func currentAlarm(for ticket: AlarmOccurrenceFinishTicket) throws -> Alarm? {
        try repository.fetchOccurrenceFinishAlarms().first { $0.id == ticket.alarmID }
    }
}
