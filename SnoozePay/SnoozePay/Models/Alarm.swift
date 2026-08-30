import Foundation

/// Domain model for an alarm. Separate from Core Data entity for clean MVVM.
///
/// All fields are immutable (#207, interim hardening until #31 phase 2).
/// Construction goes through one of three boundaries:
/// - `init(validating:...)` — failable, rejects out-of-range values. Use it
///   whenever the field values come from outside the app's bounded UI
///   controls (imports, future deep links, manual copies).
/// - `init(...)` — the historical default-arg initializer. Delegates to the
///   validating one and traps on garbage, so in-app call sites (which only
///   feed slider/toggle-bounded values) keep their non-optional ergonomics.
/// - `init(from:)` — Codable decode. Sanitizes instead of rejecting, because
///   throwing here would lock the entire persisted store (#72 / #117).
///
/// Legitimate edits produce a new value via `with(...)`.
struct Alarm: Identifiable, Equatable, Codable {
    let id: UUID
    let time: Date
    let repeatDays: [Int] // 0 = Monday, 6 = Sunday
    let name: String
    let soundID: String
    let vibrationEnabled: Bool
    let snoozeMinutes: Int
    let penaltyAmount: Double
    let progressiveScale: Bool
    let enabled: Bool
    /// Per-alarm playback volume in `0.0...1.0`. Default `1.0` keeps the
    /// existing "ring at full volume" behaviour for legacy alarms (#150).
    let volume: Float
    /// When `true`, AudioService ramps from 0 → `volume` over 30 seconds at
    /// firing time so the user is woken gently. Default `false` preserves the
    /// pre-#150 instant-on behaviour.
    let volumeFadeIn: Bool
    /// Visual theme used for the alarm-card background strip and the firing
    /// screen background (#151). Defaults to `.dawn` for both new alarms and
    /// legacy alarms persisted before the theme picker landed — see the
    /// custom `init(from:)` below for the migration path.
    let theme: AlarmTheme
    /// Weekly vs one-shot recurrence (#229). Defaults to `.weekly` for both
    /// new alarms and legacy alarms persisted before the repeat-mode control
    /// landed — see the custom `init(from:)` below for the migration path.
    let repeatMode: AlarmRepeatMode

    // MARK: - Validation rules (#207)

    /// Canonical range for snooze duration: 1–15 minutes. The design canon
    /// (chat1.md:996 — per-alarm slider 1–15 min) is the source of truth; the
    /// older "1–30" SPEC wording was stale and has since been aligned (#302).
    /// `CreateAlarmViewModel.snoozeMinutesRange` already bounds the create/edit
    /// slider to this same range. Legacy alarms persisted with snoozeMinutes
    /// 16–30 are clamped to 15 on decode (see `init(from:)`), never dropped.
    static let snoozeMinutesRange: ClosedRange<Int> = 1...15
    /// Legal weekday indices for `repeatDays` (0 = Monday, 6 = Sunday).
    static let weekdayIndexRange: ClosedRange<Int> = 0...6

    /// The name a new alarm carries until the user types one of their own.
    /// Read by both initializers here and by `CreateAlarmViewModel`.
    ///
    /// Computed rather than stored to match how the rest of the catalogue is
    /// read (``Plural``, `Localized.text` call sites): a missing key should
    /// surface wherever it is used, not hide behind whichever call site
    /// happened to initialize a `static let` first. Today that is a
    /// consistency argument and nothing more — `Localized.bundle` is itself a
    /// `static let` resolved once per process, so a stored copy would hold the
    /// same string.
    ///
    /// ⚠️ This value is **persisted** into `Alarm.name`, which makes it a
    /// sentinel as well as copy: `AlarmsListViewModel.weekdayPhrase` suppresses
    /// the default name in the caps row by comparing against it. That
    /// comparison is against a literal on purpose and breaks once a second
    /// language ships — see #623, which owns the model change that fixes it.
    static var defaultName: String { Localized.text("alarms.default_name") }

    // MARK: - Validating failable init (#207)

    /// Validating construction boundary. Returns `nil` when:
    /// - any `repeatDays` element falls outside `weekdayIndexRange`
    /// - `snoozeMinutes` falls outside `snoozeMinutesRange`
    /// - `penaltyAmount` is negative or non-finite (NaN / infinity)
    ///
    /// `volume` is clamped into `0...1` (non-finite → full volume) rather
    /// than rejected, preserving the historical initializer's behaviour.
    init?(
        validating id: UUID,
        time: Date = Date(),
        repeatDays: [Int] = [],
        name: String = Alarm.defaultName,
        soundID: String = "radar",
        vibrationEnabled: Bool = true,
        snoozeMinutes: Int = 9,
        penaltyAmount: Double = 50,
        progressiveScale: Bool = false,
        enabled: Bool = true,
        volume: Float = 1.0,
        volumeFadeIn: Bool = false,
        theme: AlarmTheme = .dawn,
        repeatMode: AlarmRepeatMode = .weekly
    ) {
        guard repeatDays.allSatisfy(Self.weekdayIndexRange.contains),
              Self.snoozeMinutesRange.contains(snoozeMinutes),
              penaltyAmount.isFinite, penaltyAmount >= 0
        else { return nil }

        self.id = id
        self.time = time
        self.repeatDays = repeatDays
        self.name = name
        self.soundID = soundID
        self.vibrationEnabled = vibrationEnabled
        self.snoozeMinutes = snoozeMinutes
        self.penaltyAmount = penaltyAmount
        self.progressiveScale = progressiveScale
        self.enabled = enabled
        self.volume = Self.clampedVolume(volume)
        self.volumeFadeIn = volumeFadeIn
        self.theme = theme
        self.repeatMode = repeatMode
    }

    /// Historical default-arg initializer, kept for in-app call sites whose
    /// inputs are already bounded by UI controls. Delegates to
    /// `init(validating:...)` and traps if handed garbage — invalid values
    /// must be rejected at the construction boundary, not stored (#207).
    init(
        id: UUID = UUID(),
        time: Date = Date(),
        repeatDays: [Int] = [],
        name: String = Alarm.defaultName,
        soundID: String = "radar",
        vibrationEnabled: Bool = true,
        snoozeMinutes: Int = 9,
        penaltyAmount: Double = 50,
        progressiveScale: Bool = false,
        enabled: Bool = true,
        volume: Float = 1.0,
        volumeFadeIn: Bool = false,
        theme: AlarmTheme = .dawn,
        repeatMode: AlarmRepeatMode = .weekly
    ) {
        guard let alarm = Alarm(
            validating: id,
            time: time,
            repeatDays: repeatDays,
            name: name,
            soundID: soundID,
            vibrationEnabled: vibrationEnabled,
            snoozeMinutes: snoozeMinutes,
            penaltyAmount: penaltyAmount,
            progressiveScale: progressiveScale,
            enabled: enabled,
            volume: volume,
            volumeFadeIn: volumeFadeIn,
            theme: theme,
            repeatMode: repeatMode
        ) else {
            preconditionFailure(
                """
                Alarm constructed with invalid fields \
                (repeatDays=\(repeatDays), snoozeMinutes=\(snoozeMinutes), \
                penaltyAmount=\(penaltyAmount)). \
                Use Alarm(validating:...) for unvalidated input.
                """
            )
        }
        self = alarm
    }

    // MARK: - with(...) mutators (#207)

    /// Returns a copy with the given fields replaced; `nil` arguments keep
    /// the current value. Identity (`id`) is intentionally not replaceable.
    /// Delegates to the trapping initializer, so feeding it unvalidated
    /// user input for `repeatDays` / `snoozeMinutes` / `penaltyAmount` is a
    /// programmer error — sanitize first or construct via
    /// `Alarm(validating:...)`.
    func with(
        time: Date? = nil,
        repeatDays: [Int]? = nil,
        name: String? = nil,
        soundID: String? = nil,
        vibrationEnabled: Bool? = nil,
        snoozeMinutes: Int? = nil,
        penaltyAmount: Double? = nil,
        progressiveScale: Bool? = nil,
        enabled: Bool? = nil,
        volume: Float? = nil,
        volumeFadeIn: Bool? = nil,
        theme: AlarmTheme? = nil,
        repeatMode: AlarmRepeatMode? = nil
    ) -> Alarm {
        Alarm(
            id: id,
            time: time ?? self.time,
            repeatDays: repeatDays ?? self.repeatDays,
            name: name ?? self.name,
            soundID: soundID ?? self.soundID,
            vibrationEnabled: vibrationEnabled ?? self.vibrationEnabled,
            snoozeMinutes: snoozeMinutes ?? self.snoozeMinutes,
            penaltyAmount: penaltyAmount ?? self.penaltyAmount,
            progressiveScale: progressiveScale ?? self.progressiveScale,
            enabled: enabled ?? self.enabled,
            volume: volume ?? self.volume,
            volumeFadeIn: volumeFadeIn ?? self.volumeFadeIn,
            theme: theme ?? self.theme,
            repeatMode: repeatMode ?? self.repeatMode
        )
    }

    // MARK: - Codable (backwards-compatible decode)
    //
    // `volume` + `volumeFadeIn` were added in #150 and `theme` in #151.
    // Pre-#150 / pre-#151 stored alarms do not carry these keys —
    // `decodeIfPresent` plus the documented defaults keeps existing JSON
    // readable without forcing a migration step. Synthesized Codable would
    // throw `keyNotFound`, which `AlarmRepository.readAll()` propagates as
    // a fatal `decodeFailure` (issue #117 / #72 lock the entire store).
    // Adding a field MUST be backward-compatible — this initializer is the
    // contract that ships safely on top of #143.
    //
    // Decode SANITIZES out-of-range legacy values instead of rejecting them
    // (#207): pre-validation installs may carry snoozeMinutes outside the
    // spec range, garbage weekday indices, or a negative penalty. Throwing
    // would lock the whole store; trapping would crash on launch. Clamping /
    // dropping keeps every legacy alarm readable while guaranteeing decoded
    // values satisfy the same invariants `init(validating:...)` enforces.

    private enum CodingKeys: String, CodingKey {
        case id, time, repeatDays, name, soundID, vibrationEnabled
        case snoozeMinutes, penaltyAmount, progressiveScale, enabled
        case volume, volumeFadeIn, theme, repeatMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.time = try container.decode(Date.self, forKey: .time)
        // Drop illegal weekday indices from corrupt legacy storage.
        let rawRepeatDays = try container.decode([Int].self, forKey: .repeatDays)
        self.repeatDays = rawRepeatDays.filter(Self.weekdayIndexRange.contains)
        self.name = try container.decode(String.self, forKey: .name)
        self.soundID = try container.decode(String.self, forKey: .soundID)
        self.vibrationEnabled = try container.decode(Bool.self, forKey: .vibrationEnabled)
        // Clamp into the canonical range. Legacy alarms persisted under the
        // old 1...30 spec (or with corrupt data) carry snoozeMinutes 16–30;
        // clamp to 15 so the alarm survives rather than being dropped (#286).
        let rawSnooze = try container.decode(Int.self, forKey: .snoozeMinutes)
        self.snoozeMinutes = min(
            max(rawSnooze, Self.snoozeMinutesRange.lowerBound),
            Self.snoozeMinutesRange.upperBound
        )
        // Negative / non-finite penalties from corrupt storage degrade to 0
        // (no charge) rather than crashing or locking the store.
        let rawPenalty = try container.decode(Double.self, forKey: .penaltyAmount)
        self.penaltyAmount = rawPenalty.isFinite ? max(rawPenalty, 0) : 0
        self.progressiveScale = try container.decode(Bool.self, forKey: .progressiveScale)
        self.enabled = try container.decode(Bool.self, forKey: .enabled)
        // New in #150 — fall back to the "ring at full volume, no fade"
        // pre-#150 behaviour when keys are missing or out of range.
        let rawVolume = try container.decodeIfPresent(Float.self, forKey: .volume) ?? 1.0
        self.volume = Self.clampedVolume(rawVolume)
        self.volumeFadeIn = try container.decodeIfPresent(Bool.self, forKey: .volumeFadeIn) ?? false
        // Migration: pre-#151 alarms have no `theme` field — default to .dawn.
        self.theme = try container.decodeIfPresent(AlarmTheme.self, forKey: .theme) ?? .dawn
        // Migration: pre-#229 alarms have no `repeatMode` field — default to
        // .weekly (the historical behaviour). Decoding the raw string keeps
        // an unknown value (corrupt storage / rolled-back future mode) from
        // throwing and locking the whole store — sanitize to .weekly instead.
        let rawRepeatMode = try container.decodeIfPresent(String.self, forKey: .repeatMode)
        self.repeatMode = rawRepeatMode.flatMap(AlarmRepeatMode.init(rawValue:)) ?? .weekly
    }

    /// Shared volume sanitization: non-finite → full volume, then clamp 0...1.
    private static func clampedVolume(_ raw: Float) -> Float {
        min(max(raw.isFinite ? raw : 1.0, 0), 1)
    }

    /// Human-readable repeat days string (e.g. "Пн, Вт, Пт").
    ///
    /// The weekday table that used to live here is gone: the names now come
    /// from `Weekday.localizedShortName`, i.e. from CLDR via `WeekdayNames`,
    /// which is the same source the caps row and the day picker read. Only the
    /// bucket labels («Единожды», «Будни») are catalogue copy.
    ///
    /// Out-of-range indices are dropped exactly as the file-local `[safe:]`
    /// subscript dropped them — that is what `Weekday(legacyMondayFirstIndex:)`
    /// being failable buys, and it is why the subscript could go with the table.
    var repeatDaysDescription: String {
        guard !repeatDays.isEmpty else { return Localized.text("alarms.days.once") }

        let allWeekdays = [0, 1, 2, 3, 4]
        let allWeekend = [5, 6]

        let sorted = repeatDays.sorted()

        if sorted == Array(0...6) { return Localized.text("alarms.days.every_day") }
        if sorted == allWeekdays { return Localized.text("alarms.days.weekdays_plain") }
        if sorted == allWeekend { return Localized.text("alarms.days.weekend") }

        return sorted
            .compactMap { Weekday(legacyMondayFirstIndex: $0)?.localizedShortName }
            .joined(separator: ", ")
    }

    /// Next trigger date for display purposes
    var nextTriggerDate: Date? {
        if repeatDays.isEmpty {
            let now = Date()
            return time > now ? time : nil
        }
        return time
    }

    /// Penalty for a given snooze count (1-based). Applies progressive doubling
    /// if enabled, capped at a 4-step ladder — `base, ×2, ×4, ×8` (e.g.
    /// `50 → 100 → 200 → 400 ₽`). The exponent is clamped to `3` so the price
    /// never escalates past `base × 8`; counts 4, 5, 10, … all return the
    /// ceiling. Mirrors the design's `idx = min(count, 3)` rule
    /// (`SPDawnV3.jsx:149-152`, `chat1.md:256`).
    func penalty(forSnoozeCount count: Int) -> Double {
        guard progressiveScale, count > 1 else { return penaltyAmount }
        let exponent = min(count - 1, 3)
        let multiplier = pow(2.0, Double(exponent))
        return penaltyAmount * multiplier
    }

    /// `true` once `penalty(forSnoozeCount:)` has reached the `base × 8`
    /// ceiling (i.e. `count >= 4`). At the ceiling the firing screen swaps the
    /// escalating "next price" hint for the max-step copy.
    func isPenaltyAtCeiling(forSnoozeCount count: Int) -> Bool {
        progressiveScale && count >= 4
    }

    // MARK: - Typed views (phase 1 of #31)
    //
    // The fields below are the typed-domain projections of the underlying
    // primitive storage. They never mutate state — they're read-only views.
    // Phase 2 will migrate the storage itself; until then, callers can adopt
    // the typed view incrementally without invalidating persisted JSON.

    /// Wall-clock time-of-day projection of `time`. `nil` only if the
    /// calendar refuses to extract hour/minute, which doesn't happen for
    /// real `Date` values + `Calendar.current`.
    var timeOfDay: TimeOfDay? {
        TimeOfDay(from: time)
    }

    /// Typed view over `repeatDays`. Since #207 the construction boundary
    /// rejects (init) or drops (decode) out-of-range indices, so this is a
    /// straight bridge; the legacy-index skip in `Set<Weekday>` is now a
    /// belt-and-suspenders guard.
    var weekdays: Set<Weekday> {
        Set<Weekday>(legacyMondayFirstIndices: repeatDays)
    }

    /// Typed view of `penaltyAmount`. Since #207 every construction path
    /// guarantees a non-negative finite amount, so this never returns `nil`
    /// in practice; the optional shape stays until phase 2 retypes storage.
    ///
    /// `penaltyAmount` is a currency-less `Double` written before the app knew
    /// about currencies, hence the legacy bridge (#561).
    var penaltyMoney: Money? {
        Money.legacy(penaltyAmount)
    }
}
