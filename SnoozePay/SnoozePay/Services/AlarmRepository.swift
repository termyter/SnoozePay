import Foundation
import os

/// Persists alarms in UserDefaults with a serial queue protecting all reads and writes.
/// Without serialization, concurrent callers (UI edits + notification action handlers)
/// can race on read-modify-write cycles and lose updates — last writer wins.
final class AlarmRepository {

    static let shared = AlarmRepository()

    /// Errors surfaced to callers so the UI can warn the user instead of
    /// silently dropping data (issue #72).
    ///
    /// `decodeFailure` is reported by `fetchAllChecked()` when the stored
    /// JSON can't be parsed. `persistBlocked` fires from any mutating call
    /// while `lastLoadFailed == true` — we refuse to overwrite a corrupt
    /// blob from a partial in-memory snapshot, which would otherwise turn a
    /// transient decode glitch into permanent data loss. `encodeFailure` is
    /// reported when `JSONEncoder` itself rejects the model.
    enum RepositoryError: LocalizedError {
        case decodeFailure(underlying: Error)
        case encodeFailure(underlying: Error)
        case persistBlocked

        var errorDescription: String? {
            switch self {
            case .decodeFailure:
                return Localized.text("alarms.error.load_failed")
            case .encodeFailure:
                return Localized.text("alarms.error.save_failed")
            case .persistBlocked:
                return Localized.text("alarms.error.save_blocked")
            }
        }
    }

    private let key = "stored_alarms"
    /// Where the corrupt blob is copied on first decode failure so a future
    /// recovery flow / support ticket can inspect what went wrong (issue #72).
    /// Persisted under a separate key so a subsequent successful save can
    /// overwrite `key` without nuking the diagnostic snapshot.
    static let corruptBackupKey = "stored_alarms_backup_corrupt"

    private let defaults: UserDefaults
    /// Scheduler seam — production uses the singleton, tests inject a stub so
    /// they can verify error propagation (#129) without booting the real
    /// `UNUserNotificationCenter`.
    private let scheduler: AlarmScheduling
    private let queue = DispatchQueue(label: "com.snoozepay.alarms.serial")
    private static let log = OSLog(subsystem: "Ivan-Emelyanov.SnoozePay", category: "AlarmRepository")

    /// Set inside `queue.sync` whenever a decode failure is observed. While
    /// true, `persist()` refuses to write — this prevents the user from
    /// pressing "+" on what looks like an empty list and silently
    /// overwriting the corrupted (but recoverable) bytes (issue #72).
    private var _lastLoadFailed: Bool = false
    var lastLoadFailed: Bool { queue.sync { _lastLoadFailed } }

    /// Production code MUST use `AlarmRepository.shared` to avoid creating
    /// isolated instances with separate serial queues (which reintroduces the
    /// race this class exists to prevent).
    ///
    /// Tests inject a custom `UserDefaults` suite to stay isolated from app
    /// state — that's why this initializer is `internal` rather than `private`.
    /// Production call sites that pass no arguments would create an isolated
    /// instance backed by `.standard`, defeating the singleton serialization,
    /// so we deliberately omit the default value: callers must be explicit.
    init(defaults: UserDefaults, scheduler: AlarmScheduling = AlarmScheduler.shared) {
        self.defaults = defaults
        self.scheduler = scheduler
    }

    private convenience init() {
        self.init(defaults: .standard)
    }

    // MARK: - Read

    /// Lossy read: a decode failure is indistinguishable from "no alarms"
    /// (#210). Every production call site now uses `fetchAllChecked()` and
    /// decides explicitly what an unreadable store means (#271) — this
    /// variant survives only for the tests that pin the lossy contract
    /// itself, which is why it is deprecated rather than deleted.
    @available(*, deprecated, message: "Lossy: a decode failure reads as []. Use fetchAllChecked() (#271).")
    func fetchAll() -> [Alarm] {
        queue.sync { (try? readAll()) ?? [] }
    }

    /// Read variant that surfaces decode failures instead of swallowing them.
    /// `AlarmsListViewModel` uses this so a corrupt store renders a visible
    /// banner rather than the deceptive "no alarms" empty state (issue #72).
    func fetchAllChecked() throws -> [Alarm] {
        try queue.sync { try readAll() }
    }

    /// Lossy read: a decode failure is indistinguishable from "alarm doesn't
    /// exist" (#210). All production call sites moved to `fetchChecked(id:)`
    /// (#271); kept for the tests that pin the lossy contract.
    @available(*, deprecated, message: "Lossy: a decode failure reads as nil. Use fetchChecked(id:) (#271).")
    func fetch(id: UUID) -> Alarm? {
        queue.sync { (try? readAll())?.first { $0.id == id } }
    }

    /// Single-alarm read variant that surfaces decode failures instead of
    /// swallowing them. Callers on hot paths (AppDelegate presenting the
    /// firing screen, AlarmFiringCoordinator routing snooze) use this so a
    /// corrupt blob is logged + visible to the user instead of being
    /// indistinguishable from "alarm doesn't exist" (issue #117). Returns
    /// `nil` when the id is genuinely absent — only throws on decode failure.
    func fetchChecked(id: UUID) throws -> Alarm? {
        try queue.sync { try readAll().first { $0.id == id } }
    }

    // MARK: - Mutate

    /// Saves (upserts) an alarm.
    /// - Returns: `true` on successful persistence, `false` if the store is
    ///   currently locked (`lastLoadFailed == true`) or encoding fails.
    ///   Callers (CreateAlarmViewModel) surface the failure to the user
    ///   instead of pretending the alarm landed safely (issue #72).
    ///
    /// `schedulingResult` is invoked **only on the successful-persist path**
    /// once `AlarmScheduler.schedule` finishes (issue #118). Disabled alarms
    /// resolve with `.success(())` because there is no scheduling work, but
    /// the closure is still called so async callers always observe
    /// completion when `save` returned `true`. When `save` returns `false`
    /// the closure is **not** invoked — the caller has already received the
    /// failure synchronously via the boolean.
    @discardableResult
    func save(
        _ alarm: Alarm,
        schedulingResult: ((Result<Void, AlarmScheduler.SchedulingError>) -> Void)? = nil
    ) -> Bool {
        let didPersist: Bool = queue.sync {
            guard !_lastLoadFailed else { return false }
            // Read fresh state inside the lock so concurrent saves don't
            // clobber each other. If the read itself fails, persistBlocked
            // will already have been raised by the readAll() throw path.
            var alarms: [Alarm]
            do {
                alarms = try readAll()
            } catch {
                return false
            }
            if let idx = alarms.firstIndex(where: { $0.id == alarm.id }) {
                alarms[idx] = alarm
            } else {
                alarms.append(alarm)
            }
            return persist(alarms)
        }

        guard didPersist else { return false }

        scheduler.cancel(alarm.id)
        if alarm.enabled {
            scheduler.schedule(alarm, completion: schedulingResult)
        } else {
            // Disabled alarms don't schedule — report success so async
            // callers don't hang waiting for a closure that never fires.
            schedulingResult?(.success(()))
        }
        return true
    }

    @discardableResult
    func delete(id: UUID) -> Bool {
        let didPersist: Bool = queue.sync {
            guard !_lastLoadFailed else { return false }
            var alarms: [Alarm]
            do {
                alarms = try readAll()
            } catch {
                return false
            }
            alarms.removeAll { $0.id == id }
            return persist(alarms)
        }
        if didPersist {
            scheduler.cancel(id)
        }
        return didPersist
    }

    /// Toggles `enabled` on the alarm with the given id.
    /// - Parameters:
    ///   - enabled: target state for the toggle.
    ///   - id: stable UUID of the alarm to flip.
    ///   - schedulingResult: optional callback invoked **only on the
    ///     successful-persist path** once `AlarmScheduler.schedule` finishes
    ///     (issue #129). Toggling off an alarm resolves with `.success(())`
    ///     because there is no scheduling work — the closure is still called
    ///     so async callers always observe completion. When the boolean
    ///     return is `false` the closure is **not** invoked: the caller has
    ///     already received the failure synchronously.
    /// - Returns: `true` if the alarm existed and was updated; `false` if no alarm
    ///   matched the id, the store is locked, or encoding failed. Callers
    ///   (e.g. `AlarmsListViewModel`) rely on the boolean to roll back
    ///   optimistic UI flips when the underlying alarm has been deleted from
    ///   another path (issue #35) or when the store is corrupt (issue #72).
    @discardableResult
    func setEnabled(
        _ enabled: Bool,
        id: UUID,
        schedulingResult: ((Result<Void, AlarmScheduler.SchedulingError>) -> Void)? = nil
    ) -> Bool {
        let updated: Alarm? = queue.sync {
            guard !_lastLoadFailed else { return nil }
            var alarms: [Alarm]
            do {
                alarms = try readAll()
            } catch {
                return nil
            }
            guard let idx = alarms.firstIndex(where: { $0.id == id }) else { return nil }
            alarms[idx] = alarms[idx].with(enabled: enabled)
            guard persist(alarms) else { return nil }
            return alarms[idx]
        }

        guard let alarm = updated else {
            os_log(
                "setEnabled: no alarm with id %{public}@ (or store locked)",
                log: Self.log, type: .info, id.uuidString
            )
            return false
        }
        scheduler.cancel(alarm.id)
        if alarm.enabled {
            scheduler.schedule(alarm, completion: schedulingResult)
        } else {
            // Toggle-off has no scheduling work — fire `.success(())` so async
            // callers don't hang waiting for a closure that never lands.
            schedulingResult?(.success(()))
        }
        return true
    }

    // MARK: - Recovery

    /// Clears the lock and removes the corrupt blob. Used by a future
    /// "стереть и начать заново" flow once the user has acknowledged the
    /// data loss (issue #72). The diagnostic backup at `corruptBackupKey`
    /// is intentionally left in place for support inspection.
    func clearCorruptState() {
        queue.sync {
            _lastLoadFailed = false
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - Private (must be called inside queue.sync)

    /// Returns persisted alarms.
    ///
    /// Differentiates three states (issue #23 / #72):
    ///   1. Key absent — new user, returns `[]` (legitimate empty state).
    ///   2. Key present, decode succeeds — returns sorted alarms and clears
    ///      `_lastLoadFailed` so a subsequent successful read after a
    ///      transient glitch unblocks writes.
    ///   3. Key present, decode fails — copies the corrupt blob to the
    ///      backup key (once), sets `_lastLoadFailed = true`, and throws
    ///      `RepositoryError.decodeFailure`. The corrupted JSON stays on
    ///      disk untouched so it remains available for diagnosis.
    private func readAll() throws -> [Alarm] {
        guard let data = defaults.data(forKey: key) else {
            // Case 1: brand-new install — no stored alarms yet.
            _lastLoadFailed = false
            return []
        }
        do {
            let alarms = try JSONDecoder().decode([Alarm].self, from: data)
            _lastLoadFailed = false
            return alarms.sorted { $0.time < $1.time }
        } catch {
            // Case 3: stored bytes can't be decoded.
            _lastLoadFailed = true
            // Copy to backup once so successive failed reads don't hammer
            // UserDefaults with redundant writes. We treat the first failure
            // as the source-of-truth snapshot worth preserving.
            if defaults.data(forKey: Self.corruptBackupKey) == nil {
                defaults.set(data, forKey: Self.corruptBackupKey)
            }
            os_log(
                "Decode failed (%{public}d bytes preserved on disk + backup): %{public}@",
                log: Self.log, type: .error, data.count, String(describing: error)
            )
            throw RepositoryError.decodeFailure(underlying: error)
        }
    }

    /// Writes the encoded alarm list to disk.
    /// - Returns: `true` on success, `false` if encoding failed. Never writes
    ///   `nil` — that would wipe the entire alarm list silently.
    @discardableResult
    private func persist(_ alarms: [Alarm]) -> Bool {
        do {
            let data = try JSONEncoder().encode(alarms)
            defaults.set(data, forKey: key)
            return true
        } catch {
            // Don't write nil — that wipes the entire alarm list silently.
            // If encode fails the previous JSON on disk stays intact (issue #23).
            // assertionFailure is a no-op in release (issue #72) so callers
            // get a Bool back and decide whether to surface an alert.
            os_log(
                "Encode failed, previous state preserved on disk: %{public}@",
                log: Self.log, type: .error, String(describing: error)
            )
            return false
        }
    }
}
