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
    /// The name the user typed, or `nil` while the alarm still carries the
    /// auto-assigned default (#623). Storing the ABSENCE of a user name makes
    /// ``nameIsDefault`` a fact about the alarm instead of a guess made by
    /// comparing ``name`` against whatever the default reads in the language
    /// the reader runs. Persisted as `name` + `nameIsDefault` — see `encode(to:)`.
    let customName: String?
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
    /// Since #623 this is no longer a sentinel: nothing compares a persisted
    /// name against it. An alarm that never got a user-typed name stores
    /// `customName == nil` and resolves this value at DISPLAY time, so the
    /// default follows the UI language instead of freezing the language the
    /// alarm happened to be created in.
    static var defaultName: String { Localized.text("alarms.default_name") }

    /// Every string that has ever shipped as the auto-assigned default name,
    /// lowercased and trimmed. Read by the decoder ONLY, and only for records
    /// written before the `nameIsDefault` key existed — those can carry nothing
    /// but the Russian default, Russian being the only language shipped to
    /// date. The set is therefore frozen: every language shipping from here on
    /// writes the flag and never has to be inferred. Growing it would be the
    /// "compare against all historical defaults" design #623 rejected.
    ///
    /// Not a catalogue candidate (#598), and the one literal here where
    /// migrating would be an outright bug rather than a style choice: this is
    /// matched against bytes already **on disk**, written by a build that
    /// shipped only Russian. Reading it from the catalogue would compare a
    /// record's frozen past against the reader's current language, so the
    /// inference would silently stop firing for anyone not running in Russian
    /// — the language-dependent behaviour #623 removed, reintroduced through
    /// the decoder. `AlarmDefaultNameTests` covers the legacy path, down to
    /// the trimming and case-folding.
    private static let legacyDefaultNames: Set<String> = ["будильник"]  // i18n:exempt сентинел декодера на диске

    // MARK: - Name

    /// Display name: the user's own, or the default resolved in the language
    /// the app is running in right now.
    var name: String { customName ?? Alarm.defaultName }

    /// `true` while the alarm carries the auto-assigned default name, i.e. the
    /// user never typed one of their own. Provenance, not spelling: an alarm
    /// the user deliberately named "Будильник" reads `false` and keeps showing
    /// that name — hiding a typed name because it collides with today's default
    /// would be exactly the language-dependent behaviour #623 removed.
    var nameIsDefault: Bool { customName == nil }

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
        name: String? = nil,
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
        self.customName = name
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
        name: String? = nil,
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
            // A name passed here is one the caller set, so it lands as a
            // custom name; omitting it preserves whichever state the alarm was
            // already in, "still on the default" included (#623).
            name: name ?? customName,
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
    // `volume` + `volumeFadeIn` were added in #150, `theme` in #151 and
    // `nameIsDefault` in #623.
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

    /// Every key the persisted record carries. `CaseIterable` is not
    /// decoration: `allCases` is what `encode(to:)` iterates, which is what
    /// makes a key impossible to declare and then forget to write.
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id, time, repeatDays, name, nameIsDefault, soundID, vibrationEnabled
        case snoozeMinutes, penaltyAmount, progressiveScale, enabled
        case volume, volumeFadeIn, theme, repeatMode
    }

    // swiftlint:disable cyclomatic_complexity
    /// Hand-rolled because the storage key `name` no longer maps one-to-one
    /// onto a stored property: `customName` is optional, and the pair written
    /// to disk is a resolved display string plus a `nameIsDefault` flag (#623).
    /// Writing the RESOLVED name under the historical key is what keeps the
    /// record readable by a build that predates the flag — it sees what it
    /// always saw instead of throwing `keyNotFound` and locking the store.
    ///
    /// Driven off `CodingKeys.allCases` so that a forgotten field is a COMPILE
    /// error rather than a review miss (#629). A straight list of
    /// `container.encode(...)` calls has no reader but the reviewer: a field
    /// added to `init(from:)` and forgotten here builds, ships, and quietly
    /// stops being persisted — and the round-trip test does not catch it,
    /// because a fixture built through `Alarm(...)` leaves the new field at its
    /// default on BOTH sides of the trip. The cost is not a defaulted flag
    /// either: `init(from:)` drops the stored string outright when
    /// `nameIsDefault` reads `true`, so a lost key is a lost user name.
    ///
    /// The `switch` has no `default`, so a new case — which anyone adding a
    /// field must write, since `init(from:)` needs the key to read it — stops
    /// this file from building until its value is encoded. The loop visits each
    /// key exactly once and writes the same value under the same key as the
    /// straight-line version did — same key SET, same values, so the shape on
    /// disk is unchanged.
    ///
    /// Not «same bytes»: key order in the emitted JSON is Foundation's, not
    /// ours, and always was — a keyed container is dictionary-backed without
    /// `.sortedKeys`. That is fine because nothing depends on order:
    /// `JSONDecoder` looks keys up, `AlarmRepository.persist` hands the `Data`
    /// straight to `UserDefaults`, and no test compares encoded bytes. Said
    /// plainly here because this is the paragraph someone reads before
    /// touching an encoder that owns live user data — and believing an
    /// ordering guarantee that was never there is how they would «preserve»
    /// one that costs something.
    ///
    /// `AlarmCodingContractTests` pins the two things the compiler still
    /// cannot see — a property that never got a key, and an arm that writes
    /// nothing.
    ///
    /// Complexity is suppressed deliberately: fifteen arms performing one
    /// `encode` each are a table, not branching logic, and the default
    /// threshold would turn into a lint ERROR at 19 keys — complexity is
    /// `cases + 1`, the default error threshold is 20, and we are at 15 cases
    /// today. Past that, adding a field would start failing the linter instead
    /// of the compiler, which is the opposite of the point of this PR.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        for key in CodingKeys.allCases {
            switch key {
            case .id: try container.encode(id, forKey: .id)
            case .time: try container.encode(time, forKey: .time)
            case .repeatDays: try container.encode(repeatDays, forKey: .repeatDays)
            case .name: try container.encode(name, forKey: .name)
            case .nameIsDefault: try container.encode(nameIsDefault, forKey: .nameIsDefault)
            case .soundID: try container.encode(soundID, forKey: .soundID)
            case .vibrationEnabled: try container.encode(vibrationEnabled, forKey: .vibrationEnabled)
            case .snoozeMinutes: try container.encode(snoozeMinutes, forKey: .snoozeMinutes)
            case .penaltyAmount: try container.encode(penaltyAmount, forKey: .penaltyAmount)
            case .progressiveScale: try container.encode(progressiveScale, forKey: .progressiveScale)
            case .enabled: try container.encode(enabled, forKey: .enabled)
            case .volume: try container.encode(volume, forKey: .volume)
            case .volumeFadeIn: try container.encode(volumeFadeIn, forKey: .volumeFadeIn)
            case .theme: try container.encode(theme, forKey: .theme)
            case .repeatMode: try container.encode(repeatMode, forKey: .repeatMode)
            }
        }
    }
    // swiftlint:enable cyclomatic_complexity

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.time = try container.decode(Date.self, forKey: .time)
        // Drop illegal weekday indices from corrupt legacy storage.
        let rawRepeatDays = try container.decode([Int].self, forKey: .repeatDays)
        self.repeatDays = rawRepeatDays.filter(Self.weekdayIndexRange.contains)
        // Migration: pre-#623 alarms have no `nameIsDefault` key, so the flag
        // is inferred ONCE, on read, from the frozen set of names that ever
        // shipped as a default. That inference is safe precisely because such
        // records predate the second language — it is the one moment where
        // comparing a persisted name against a literal is correct.
        let storedName = try container.decode(String.self, forKey: .name)
        let storedNameIsDefault = try container.decodeIfPresent(Bool.self, forKey: .nameIsDefault)
            ?? Self.legacyDefaultNames.contains(
                storedName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            )
        self.customName = storedNameIsDefault ? nil : storedName
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

    /// The one place the ring-volume invariant lives: non-finite → full
    /// volume, then clamp to `0...1`.
    ///
    /// Deliberately not `private` (#714). The same expression used to be
    /// copy-pasted into `SoundPickerViewController`, `VolumePickerViewController`
    /// and `AudioService.configurePlayerVolume`; all four agreed, but nothing
    /// made them agree. A single copy drifting — say a NaN fallback of `0`
    /// instead of `1.0` — would have made one alarm restored from corrupt
    /// storage ring differently depending on which screen it reached, with
    /// every per-copy test still green. Callers seed from this; they do not
    /// restate it.
    ///
    /// `AlarmDefaults.volume` intentionally keeps its own expression: its
    /// fallback is the named `fallbackVolume` constant ("what a *new* alarm
    /// starts at"), a separate knob that happens to equal `1.0` today.
    static func clampedVolume(_ raw: Float) -> Float {
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
