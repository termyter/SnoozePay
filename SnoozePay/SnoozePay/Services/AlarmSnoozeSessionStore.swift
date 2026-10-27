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
    case unavailable, finished, unsupportedBackend, unconfirmedRegistration

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
        let fireDate: Date?
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
    private enum EnvelopeKeys: String, CodingKey { case version, sessions, finishRequests }
    private struct Envelope: Codable {
        var version = 1
        var sessions: [Session] = []
        /// Absent in legacy envelopes. Reads never persist an implicit migration.
        var finishRequests: [AlarmOccurrenceFinishTicket]?

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: EnvelopeKeys.self)
            version = try container.decode(Int.self, forKey: .version)
            sessions = try container.decode([Session].self, forKey: .sessions)
            // Only absence means legacy empty. A present null is unknown safety
            // metadata, not proof that no finish quarantine remains.
            finishRequests = container.contains(.finishRequests)
                ? try container.decode([AlarmOccurrenceFinishTicket].self, forKey: .finishRequests) : nil
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: EnvelopeKeys.self)
            try container.encode(version, forKey: .version)
            try container.encode(sessions, forKey: .sessions)
            try container.encodeIfPresent(finishRequests, forKey: .finishRequests)
        }
    }

    // Main-actor physical operations survive finish until their callback settles.
    private static var running: Set<AlarmSnoozeToken> = []
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
        return Snapshot(sessionID: session.id, alarmID: session.alarmID, count: session.count,
                        fireDate: session.attempts.last?.receipt?.fireDate)
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
        guard !(envelope.finishRequests ?? []).contains(where: { $0.alarmID == alarmID }) else {
            throw AlarmSnoozeContextError.unavailable
        }
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
                  session.alarmID == alarmID
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
        Self.running.insert(token)
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
        Self.running.remove(token)
    }

    func pendingCount(_ token: AlarmSnoozeToken, alarmID: UUID) throws -> Int {
        let envelope = try read()
        guard !(envelope.finishRequests ?? []).contains(where: { $0.alarmID == alarmID }) else {
            throw AlarmSnoozeContextError.unavailable
        }
        let session = try find(token, alarmID: alarmID, in: envelope)
        guard !session.finished, session.attempts.last?.id == token.attemptID,
              session.attempts.last?.phase == .charged else { throw AlarmSnoozeContextError.unavailable }
        return session.count
    }

    /// Called when the physical callback ends. Durable pending phases still quarantine the alarm
    /// until checked cleanup settles them.
    func operationEnded(_ token: AlarmSnoozeToken) { Self.running.remove(token) }

    func settleCancelled(alarmID: UUID) throws {
        var envelope = try read()
        var changed = false
        for index in envelope.sessions.indices where envelope.sessions[index].alarmID == alarmID
            && envelope.sessions[index].finished {
            for attempt in envelope.sessions[index].attempts.indices {
                let value = envelope.sessions[index].attempts[attempt]
                let token = AlarmSnoozeToken(sessionID: envelope.sessions[index].id, attemptID: value.id)
                guard !Self.running.contains(token) else { continue }
                if value.phase == .reserved || value.phase == .charged {
                    envelope.sessions[index].attempts[attempt].phase = value.phase == .charged ? .failed : .rejected
                    changed = true
                }
            }
        }
        guard changed else { return }
        try write(envelope)
    }

    func finish(alarmID: UUID) throws {
        var envelope = try read()
        var changed = false
        for index in envelope.sessions.indices where envelope.sessions[index].alarmID == alarmID
            && !envelope.sessions[index].finished {
            envelope.sessions[index].finished = true
            changed = true
        }
        guard changed else { return }
        try write(envelope)
    }

    // MARK: - Scoped occurrence finish

    func beginOccurrenceFinish(
        alarmID: UUID, reference: AlarmSnoozeReference?
    ) throws -> AlarmOccurrenceFinishTicket {
        var envelope = try readForOccurrenceFinish()
        let token: AlarmSnoozeToken?
        switch reference {
        case .token(let value)?: token = value
        case .unavailable?: throw AlarmOccurrenceFinishError.ownershipUnavailable
        case nil: token = nil
        }
        if let existing = envelope.finishRequests?.first(where: { $0.alarmID == alarmID }) {
            guard existing.token == token else { throw AlarmOccurrenceFinishError.ownershipUnavailable }
            _ = try finishSession(existing, in: envelope, allowFinished: true)
            return existing
        }
        let ticket = AlarmOccurrenceFinishTicket(id: UUID(), alarmID: alarmID, token: token)
        _ = try finishSession(ticket, in: envelope, allowFinished: false)
        envelope.finishRequests = (envelope.finishRequests ?? []) + [ticket]
        try writeForOccurrenceFinish(envelope)
        return ticket
    }

    func pendingOccurrenceFinish(alarmID: UUID) throws -> AlarmOccurrenceFinishTicket? {
        let envelope = try readForOccurrenceFinish()
        guard let ticket = envelope.finishRequests?.first(where: { $0.alarmID == alarmID }) else { return nil }
        _ = try finishSession(ticket, in: envelope, allowFinished: true)
        return ticket
    }

    /// Discovery for an explicit recovery action, including after process death.
    /// A live callback keeps its row discoverable; validation at retry remains busy.
    /// Enumeration itself never creates a session, releases quarantine or writes bytes.
    func pendingOccurrenceFinishes() throws -> [AlarmOccurrenceFinishTicket] {
        let envelope = try readForOccurrenceFinish()
        let tickets = envelope.finishRequests ?? []
        for ticket in tickets {
            _ = try finishSession(ticket, in: envelope, allowFinished: true)
        }
        return tickets.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    func validateOccurrenceFinish(_ ticket: AlarmOccurrenceFinishTicket) throws -> AlarmSnoozeReceipt? {
        try validatedFinishReceipt(ticket, in: readForOccurrenceFinish())
    }

    func commitOccurrenceFinish(_ ticket: AlarmOccurrenceFinishTicket) throws {
        var envelope = try readForOccurrenceFinish()
        _ = try validatedFinishReceipt(ticket, in: envelope)
        if let token = ticket.token {
            guard let index = envelope.sessions.firstIndex(where: { $0.id == token.sessionID }) else {
                throw AlarmOccurrenceFinishError.ownershipUnavailable
            }
            envelope.sessions[index].finished = true
            // The caller confirmed native cleanup. Preserve attempt counts and
            // receipts; only settle this session's no-longer-running uncertainty.
            for attempt in envelope.sessions[index].attempts.indices {
                switch envelope.sessions[index].attempts[attempt].phase {
                case .charged: envelope.sessions[index].attempts[attempt].phase = .failed
                case .reserved: envelope.sessions[index].attempts[attempt].phase = .rejected
                case .scheduled, .failed, .rejected: break
                }
            }
        }
        let remaining = (envelope.finishRequests ?? []).filter { $0.id != ticket.id }
        envelope.finishRequests = remaining.isEmpty ? nil : remaining
        try writeForOccurrenceFinish(envelope)
    }

    private func validatedFinishReceipt(
        _ ticket: AlarmOccurrenceFinishTicket, in envelope: Envelope
    ) throws -> AlarmSnoozeReceipt? {
        guard envelope.finishRequests?.first(where: { $0.id == ticket.id }) == ticket else {
            throw AlarmOccurrenceFinishError.ownershipUnavailable
        }
        let session = try finishSession(ticket, in: envelope, allowFinished: true)
        // A live physical callback remains busy even after a session was finished.
        // Durable pending without a live callback returns no receipt: the native
        // finisher must prove derived absence, not delete an unconfirmed owner.
        let busy = envelope.sessions.contains { value in
            value.alarmID == ticket.alarmID && value.attempts.contains { attempt in
                Self.running.contains(.init(sessionID: value.id, attemptID: attempt.id))
            }
        }
        guard !busy else { throw AlarmOccurrenceFinishError.busy }
        return session?.attempts.last?.receipt
    }

    private func finishSession(
        _ ticket: AlarmOccurrenceFinishTicket, in envelope: Envelope, allowFinished: Bool
    ) throws -> Session? {
        let sameAlarm = envelope.sessions.filter { $0.alarmID == ticket.alarmID }
        guard let token = ticket.token else {
            guard !sameAlarm.contains(where: { !$0.finished }) else {
                throw AlarmOccurrenceFinishError.ownershipUnavailable
            }
            return nil
        }
        guard let session = sameAlarm.first(where: { $0.id == token.sessionID }),
              session.attempts.last?.id == token.attemptID,
              allowFinished || !session.finished,
              !sameAlarm.contains(where: { $0.id != session.id && !$0.finished }) else {
            throw AlarmOccurrenceFinishError.ownershipUnavailable
        }
        return session
    }

    private func readForOccurrenceFinish() throws -> Envelope {
        do { return try read() } catch { throw AlarmOccurrenceFinishError.sessionUnavailable }
    }

    private func writeForOccurrenceFinish(_ envelope: Envelope) throws {
        do { try write(envelope) } catch { throw AlarmOccurrenceFinishError.persistenceFailed }
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
        let requests = envelope.finishRequests ?? []
        guard Set(requests.map(\.id)).count == requests.count,
              Set(requests.map(\.alarmID)).count == requests.count,
              requests.allSatisfy({ request in
                  let sameAlarm = envelope.sessions.filter { $0.alarmID == request.alarmID }
                  guard let token = request.token else { return !sameAlarm.contains { !$0.finished } }
                  return sameAlarm.contains {
                      $0.id == token.sessionID && $0.attempts.last?.id == token.attemptID
                  } && !sameAlarm.contains { $0.id != token.sessionID && !$0.finished }
              }) else { throw AlarmSnoozeContextError.unavailable }
        return envelope
    }

    private func write(_ envelope: Envelope) throws {
        let data = try JSONEncoder().encode(envelope)
        defaults.set(data, forKey: Self.key)
        guard defaults.data(forKey: Self.key) == data else { throw AlarmSnoozeContextError.unavailable }
    }
}
