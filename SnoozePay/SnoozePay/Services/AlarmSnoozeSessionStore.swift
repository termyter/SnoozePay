import Foundation

struct AlarmSnoozeToken: Codable, Equatable, Hashable {
    let sessionID: UUID
    let attemptID: UUID
}

struct AlarmSnoozeReceipt: Codable, Equatable {
    let systemID: UUID
    let fireDate: Date
}

enum AlarmSnoozeReference: Equatable {
    case token(AlarmSnoozeToken)
    case unavailable
}

enum AlarmSnoozeContextError: LocalizedError {
    case unavailable, finished, unsupportedBackend

    var errorDescription: String? { Localized.text("firing.progression.unavailable") }
}

/// Tracks new in-app sessions only. No calendar/ledger reconstruction or age reset.
/// Every mutation rereads checked bytes on the main actor; corrupt data is never overwritten.
@MainActor
final class AlarmSnoozeSessionStore {
    static let shared = AlarmSnoozeSessionStore(defaults: .standard)
    static let key = "alarm_snooze_sessions_v1"

    struct Snapshot: Equatable {
        let sessionID: UUID
        let alarmID: UUID
        let count: Int
    }

    private enum Phase: String, Codable { case reserved, charged, scheduled, failed, rejected }
    private struct Attempt: Codable {
        let id: UUID
        var phase: Phase
        var receipt: AlarmSnoozeReceipt?
    }
    private struct Session: Codable {
        let id: UUID
        let alarmID: UUID
        var count: Int
        var finished = false
        var attempts: [Attempt] = []
    }
    private struct Envelope: Codable {
        var version = 1
        var sessions: [Session] = []
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults) { self.defaults = defaults }

    func resolve(_ token: AlarmSnoozeToken, alarmID: UUID) throws -> Snapshot {
        let envelope = try read()
        let session = try find(token, alarmID: alarmID, in: envelope)
        guard !session.finished else { throw AlarmSnoozeContextError.finished }
        guard let attempt = session.attempts.first(where: { $0.id == token.attemptID }),
              attempt.phase == .scheduled || attempt.phase == .failed,
              !session.attempts.contains(where: { $0.phase == .reserved || $0.phase == .charged }) else {
            throw AlarmSnoozeContextError.unavailable
        }
        return Snapshot(sessionID: session.id, alarmID: session.alarmID, count: session.count)
    }

    /// Equality against the actual confirmed fixed schedule, never the latest record or `now`.
    func token(for receipt: AlarmSnoozeReceipt, alarmID: UUID) throws -> AlarmSnoozeToken {
        let matches = try read().sessions.flatMap { session in
            session.attempts.compactMap { attempt -> AlarmSnoozeToken? in
                guard session.alarmID == alarmID, attempt.receipt == receipt else { return nil }
                return AlarmSnoozeToken(sessionID: session.id, attemptID: attempt.id)
            }
        }
        guard matches.count == 1, let token = matches.first else { throw AlarmSnoozeContextError.unavailable }
        _ = try resolve(token, alarmID: alarmID)
        return token
    }

    /// Durable reservation BEFORE debit: a process death at the money boundary stays unknown.
    func reserve(alarmID: UUID, sessionID: UUID?, expectedCount: Int) throws -> AlarmSnoozeToken {
        var envelope = try read()
        let id = sessionID ?? UUID()
        if sessionID == nil {
            envelope.sessions.append(Session(id: id, alarmID: alarmID, count: expectedCount))
        }
        guard let index = envelope.sessions.firstIndex(where: { $0.id == id }),
              envelope.sessions[index].alarmID == alarmID,
              !envelope.sessions[index].finished,
              envelope.sessions[index].count == expectedCount,
              expectedCount >= 0, expectedCount < Int.max - 2,
              !envelope.sessions.contains(where: { session in
                  session.alarmID == alarmID && !session.finished
                      && session.attempts.contains { $0.phase == .reserved || $0.phase == .charged }
              }) else { throw AlarmSnoozeContextError.unavailable }
        let token = AlarmSnoozeToken(sessionID: id, attemptID: UUID())
        envelope.sessions[index].attempts.append(Attempt(id: token.attemptID, phase: .reserved))
        try write(envelope)
        return token
    }

    func recordCharge(_ token: AlarmSnoozeToken, alarmID: UUID) throws {
        try mutate(token, alarmID: alarmID) { session, attempt in
            guard attempt.phase == .reserved else { throw AlarmSnoozeContextError.unavailable }
            session.count += 1
            attempt.phase = .charged
        }
    }

    func rejectCharge(_ token: AlarmSnoozeToken, alarmID: UUID) throws {
        try mutate(token, alarmID: alarmID) { _, attempt in
            guard attempt.phase == .reserved else { throw AlarmSnoozeContextError.unavailable }
            attempt.phase = .rejected
        }
    }

    func complete(
        _ token: AlarmSnoozeToken, alarmID: UUID, receipt: AlarmSnoozeReceipt?
    ) throws {
        try mutate(token, alarmID: alarmID) { _, attempt in
            guard attempt.phase == .charged else { throw AlarmSnoozeContextError.unavailable }
            attempt.phase = receipt == nil ? .failed : .scheduled
            attempt.receipt = receipt
        }
    }

    func finish(alarmID: UUID) throws {
        var envelope = try read()
        for index in envelope.sessions.indices where envelope.sessions[index].alarmID == alarmID {
            envelope.sessions[index].finished = true
        }
        try write(envelope)
    }

    private func mutate(
        _ token: AlarmSnoozeToken, alarmID: UUID,
        body: (inout Session, inout Attempt) throws -> Void
    ) throws {
        var envelope = try read()
        let session = try find(token, alarmID: alarmID, in: envelope)
        guard !session.finished else { throw AlarmSnoozeContextError.finished }
        guard let index = envelope.sessions.firstIndex(where: { $0.id == token.sessionID }),
              let attemptIndex = session.attempts.firstIndex(where: { $0.id == token.attemptID }),
              attemptIndex == session.attempts.count - 1 else { throw AlarmSnoozeContextError.unavailable }
        var changed = session
        var attempt = changed.attempts[attemptIndex]
        try body(&changed, &attempt)
        changed.attempts[attemptIndex] = attempt
        envelope.sessions[index] = changed
        try write(envelope)
    }

    private func find(_ token: AlarmSnoozeToken, alarmID: UUID, in envelope: Envelope) throws -> Session {
        guard let session = envelope.sessions.first(where: { $0.id == token.sessionID }),
              session.alarmID == alarmID,
              session.attempts.contains(where: { $0.id == token.attemptID }) else {
            throw AlarmSnoozeContextError.unavailable
        }
        return session
    }

    private func read() throws -> Envelope {
        guard let data = defaults.data(forKey: Self.key) else {
            guard defaults.object(forKey: Self.key) == nil else { throw AlarmSnoozeContextError.unavailable }
            return Envelope()
        }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.version == 1,
              Set(envelope.sessions.map(\.id)).count == envelope.sessions.count,
              envelope.sessions.allSatisfy({ session in
                  session.count >= 0 && session.count < Int.max - 2
                      && Set(session.attempts.map(\.id)).count == session.attempts.count
                      && session.count >= session.attempts.filter {
                          $0.phase == .charged || $0.phase == .scheduled || $0.phase == .failed
                      }.count
                      && session.attempts.allSatisfy {
                          ($0.phase == .scheduled) == ($0.receipt != nil)
                              && ($0.receipt?.fireDate.timeIntervalSince1970.isFinite ?? true)
                      }
              }) else { throw AlarmSnoozeContextError.unavailable }
        return envelope
    }

    private func write(_ envelope: Envelope) throws {
        let data = try JSONEncoder().encode(envelope)
        defaults.set(data, forKey: Self.key)
        guard defaults.data(forKey: Self.key) == data else { throw AlarmSnoozeContextError.unavailable }
    }
}
