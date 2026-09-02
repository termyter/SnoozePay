import Foundation
import AudioToolbox
import os

/// ViewModel for create/edit alarm screen.
final class CreateAlarmViewModel {

    // MARK: - Dependencies

    private let alarmRepository: AlarmRepository

    // MARK: - Editable state (bound to UI controls)

    var time: Date
    var repeatDays: [Int]
    var name: String
    var soundID: String
    var vibrationEnabled: Bool
    var snoozeMinutes: Int
    var penaltyAmount: Double
    var progressiveScale: Bool
    var enabled: Bool
    /// Per-alarm playback volume (#150). `0...1`, default `1.0`.
    var volume: Float
    /// Per-alarm "ramp from 0 → volume over 30 seconds" toggle (#150).
    var volumeFadeIn: Bool
    var theme: AlarmTheme
    /// Weekly vs one-shot recurrence (#229). Bound to the Никогда /
    /// Еженедельно pill under the day chips.
    var repeatMode: AlarmRepeatMode

    private let existingID: UUID?

    var isEditing: Bool { existingID != nil }

    // MARK: - Init

    /// Allowed range for `snoozeMinutes`. The form's slider exposes 1...15 only
    /// (#143); editing legacy alarms persisted with values outside that range
    /// must clamp on load so the slider can render the value without crashing.
    static let snoozeMinutesRange: ClosedRange<Int> = 1...15

    init(
        alarm: Alarm? = nil,
        repository: AlarmRepository = .shared,
        defaults: AlarmDefaults = .shared
    ) {
        self.alarmRepository = repository
        self.existingID = alarm?.id

        // Seed from existing alarm or — for a brand-new alarm — the user's
        // global defaults (#283). Editing an existing alarm always keeps its
        // own saved values; only `alarm == nil` falls through to the defaults.
        self.time = alarm?.time ?? Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date()
        let seededDays = alarm?.repeatDays ?? []
        self.repeatDays = seededDays
        // New alarms start with an empty name so the form shows the
        // "Название" placeholder (#231); `makeAlarmFromCurrentState` leaves the
        // name unset when the user saves without typing one.
        //
        // An alarm that is still on the auto-assigned default seeds an empty
        // field too (#623). Echoing the default into the field would turn it
        // into a user-typed name on the very next save — the alarm would start
        // showing "БУДИЛЬНИК · …" in the caps row just because it was opened.
        self.name = alarm.map { $0.nameIsDefault ? "" : $0.name } ?? ""
        self.soundID = alarm?.soundID ?? "radar"
        self.vibrationEnabled = alarm?.vibrationEnabled ?? defaults.vibrationEnabled
        // Clamp legacy values silently — pre-#143 alarms could store up to 30
        // minutes (old stepper range). The form's slider now caps at 15.
        let rawSnooze = alarm?.snoozeMinutes ?? defaults.snoozeMinutes
        self.snoozeMinutes = min(max(rawSnooze, Self.snoozeMinutesRange.lowerBound), Self.snoozeMinutesRange.upperBound)
        self.penaltyAmount = alarm?.penaltyAmount ?? defaults.penaltyAmount
        self.progressiveScale = alarm?.progressiveScale ?? defaults.progressiveScale
        self.enabled = alarm?.enabled ?? true
        self.volume = alarm?.volume ?? defaults.volume
        self.volumeFadeIn = alarm?.volumeFadeIn ?? false
        self.theme = alarm?.theme ?? .dawn
        self.repeatMode = Self.openingRepeatMode(stored: alarm?.repeatMode ?? .weekly, days: seededDays)
    }

    /// The mode the form must OPEN in, given the stored mode and day set (#633).
    ///
    /// «Еженедельно» with an empty day set is not a schedule: `AlarmKitScheduler`
    /// builds `.never` recurrence for it, and the list row reads «ЕДИНОЖДЫ». The
    /// form used to open in exactly that state and then save it — the user saw
    /// «Еженедельно» plus «повторяться каждую неделю», and got a one-shot alarm
    /// with no warning. So the opening mode follows the days:
    ///
    /// - new alarm (no days yet) → `.never`, which is what saving right away
    ///   actually produces;
    /// - alarm stored as weekly with zero days (created by the old form) →
    ///   `.never` too, because that is how it has been ringing all along;
    /// - anything with days → its own stored mode, untouched.
    ///
    /// This is not the silent substitution the issue is about: it replaces a
    /// default (or a lie about an existing alarm) with the truth BEFORE the user
    /// makes a choice. Once they do choose «Еженедельно», the choice is honoured
    /// or refused — never quietly downgraded, see ``validationError``.
    static func openingRepeatMode(stored: AlarmRepeatMode, days: [Int]) -> AlarmRepeatMode {
        days.isEmpty ? .never : stored
    }

    // MARK: - Validation (#633)

    /// Why the current form state cannot be saved.
    ///
    /// `LocalizedError` so the view-controller can push it through the same
    /// `presentSaveError(title:error:)` path as the persist / schedule
    /// failures instead of inventing a second alert flavour.
    enum ValidationError: Error, Equatable, LocalizedError {
        /// «Еженедельно» selected with no weekday chips lit. Previously saved
        /// as a one-shot alarm with no indication that the mode had changed.
        case weeklyWithoutDays

        /// What the user reads. Non-optional so the hint under the pill can
        /// use it directly — the two must say the same thing.
        var message: String {
            switch self {
            case .weeklyWithoutDays:
                return Localized.text("create_alarm.validation.weekly_without_days")
            }
        }

        var errorDescription: String? { message }
    }

    /// The reason the form is currently unsavable, or `nil` when it is fine.
    var validationError: ValidationError? {
        repeatMode == .weekly && repeatDays.isEmpty ? .weeklyWithoutDays : nil
    }

    /// Whether «Готово» / «Сохранить» may be tapped. The controller mirrors
    /// this onto the button's `isEnabled`; `save` enforces it regardless, so
    /// a missed UI refresh cannot resurrect the silent downgrade.
    var canSave: Bool { validationError == nil }

    // MARK: - Save

    /// Outcome of `save()` reported to the view-controller.
    /// `persistFailed` mirrors the original `false` return from #72 — the
    /// store rejected the write (locked / encode error). `schedulingFailed`
    /// is the new failure path from #118 — persistence succeeded but the
    /// notification request itself didn't register, which historically
    /// surfaced as a fake "Будильник создан" toast on a silently dropped
    /// alarm.
    /// `invalid` is #633 — the form describes a schedule the app cannot build
    /// («Еженедельно» with zero days). It used to be persisted as a one-shot
    /// alarm, i.e. a different mode than the one on screen, without a word.
    enum SaveOutcome: Equatable {
        case success
        case persistFailed
        case schedulingFailed(AlarmScheduler.SchedulingError)
        case invalid(ValidationError)
    }

    /// Save the alarm and report the outcome asynchronously.
    /// Persistence is synchronous, so `.persistFailed` resolves on the
    /// caller's queue; the schedule branch resolves on main once the
    /// notification request lands or fails (issue #118).
    /// The repository contract guarantees `schedulingResult` only fires on
    /// the successful-persist path, so we never deliver two outcomes.
    func save(completion: @escaping (SaveOutcome) -> Void) {
        // Refuse before touching the store (#633): persisting here would write
        // a mode the screen does not show.
        if let error = validationError {
            completion(.invalid(error))
            return
        }

        let alarm = makeAlarmFromCurrentState()

        let didPersist = alarmRepository.save(alarm) { schedulingResult in
            switch schedulingResult {
            case .success:
                completion(.success)
            case .failure(let error):
                completion(.schedulingFailed(error))
            }
        }

        if !didPersist {
            completion(.persistFailed)
        }
    }

    /// Synchronous persist-only save — kept for legacy call sites and unit
    /// tests that don't care about the scheduling outcome (issue #72 used
    /// the boolean to gate the dismiss path before #118 introduced the
    /// scheduling failure path).
    /// Returns `false` for an invalid form too (#633) — "nothing was saved" is
    /// what the boolean has always meant, and the reason is in
    /// ``validationError``.
    @discardableResult
    func save() -> Bool {
        guard canSave else { return false }
        return alarmRepository.save(makeAlarmFromCurrentState())
    }

    private func makeAlarmFromCurrentState() -> Alarm {
        // Explicit re-construction with validated input (#207). The form's
        // controls are bounded (sliders/toggles), but `Alarm.init` now traps
        // on out-of-range values — sanitize here so a future control change
        // (e.g. a free-text penalty field) degrades gracefully instead of
        // crashing at the construction boundary.
        let safeSnooze = min(
            max(snoozeMinutes, Alarm.snoozeMinutesRange.lowerBound),
            Alarm.snoozeMinutesRange.upperBound
        )
        let safePenalty = penaltyAmount.isFinite ? max(penaltyAmount, 0) : 50
        let safeRepeatDays = repeatDays.filter(Alarm.weekdayIndexRange.contains)
        return Alarm(
            id: existingID ?? UUID(),
            time: time,
            repeatDays: safeRepeatDays,
            // Empty field → no user name at all, rather than a copy of the
            // default frozen into storage in today's language (#623).
            name: name.isEmpty ? nil : name,
            soundID: soundID,
            vibrationEnabled: vibrationEnabled,
            snoozeMinutes: safeSnooze,
            penaltyAmount: safePenalty,
            progressiveScale: progressiveScale,
            enabled: enabled,
            volume: volume,
            volumeFadeIn: volumeFadeIn,
            theme: theme,
            repeatMode: repeatMode
        )
    }

    // MARK: - Delete

    /// Removes the alarm being edited. Returns `false` for new (unsaved) alarms,
    /// where there is nothing to delete — the caller should treat this case as a
    /// no-op (the user can simply cancel out of the create screen instead).
    /// Also returns `false` when persistence is locked due to a corrupt
    /// store (issue #72) — the caller should surface that to the user.
    /// Cancelling the scheduled notification is handled by `AlarmRepository.delete`.
    @discardableResult
    func delete() -> Bool {
        guard let id = existingID else { return false }
        return alarmRepository.delete(id: id)
    }

    // MARK: - Repeat mode (#229)

    /// One-line explanation of the selected repeat mode, rendered under the
    /// Никогда / Еженедельно pill so the user understands what changes
    /// without leaving the screen (`SPScreensV2.jsx` RepeatSegmented).
    ///
    /// The hint also carries the validation copy (#633): it is the one line on
    /// the screen that already explains the repeat behaviour, so an unsavable
    /// combination says so there rather than in a modal the user meets only
    /// after tapping a button that no longer works. Both zero-day cases are
    /// spelled out — "по выбранным дням" with nothing selected was the promise
    /// the old form failed to keep.
    ///
    /// All four branches read the catalogue (#599); the validation branch goes
    /// through ``ValidationError/message`` so the hint and the save-blocked
    /// alert cannot drift onto two different keys.
    var repeatModeHint: String {
        let noDays = repeatDays.isEmpty
        switch repeatMode {
        case .never:
            return noDays
                ? Localized.text("create_alarm.repeat.hint.once")
                : Localized.text("create_alarm.repeat.hint.once_on_days")
        case .weekly:
            return noDays
                ? ValidationError.weeklyWithoutDays.message
                : Localized.text("create_alarm.repeat.hint.weekly")
        }
    }

    // MARK: - Day toggle helpers

    func toggleDay(_ day: Int) {
        if repeatDays.contains(day) {
            repeatDays.removeAll { $0 == day }
        } else {
            repeatDays.append(day)
            repeatDays.sort()
        }
    }

    // MARK: - Progressive scale preview text

    /// The four doubling steps of the progressive penalty in roubles —
    /// `[base, ×2, ×4, ×8]`. Drives the `50 → 100 → 200 → 400 ₽` chain on
    /// the progressive card (#231). Non-finite penalty input degrades to the
    /// default 50 ₽ base, mirroring `makeAlarmFromCurrentState`.
    ///
    /// Doubling is computed on `Double` via `pow(2.0, …)` so the preview
    /// follows the same doubling progression as the canonical charge engine
    /// `Alarm.penalty(forSnoozeCount:)` (which multiplies on `Double`), instead
    /// of the old truncate-then-shift `Int(base) << $0` that diverged on
    /// fractional bases (49.5 ₽ → 49/98/196/392 vs the engine's 49.5/99/198/396).
    /// Each rung is then rounded to whole roubles for display, so a fractional
    /// base shows e.g. `50/99/198/396` — the doubling matches the engine; only
    /// the display is rounded. The final `Int` conversion is clamped to avoid
    /// trapping on an absurdly large penalty — `PenaltyCell` enforces only a
    /// minimum, no upper bound (#373).
    var progressiveChain: [Int] {
        let base = penaltyAmount.isFinite ? max(penaltyAmount, 0) : 50
        return (0..<4).map { step in
            let value = (base * pow(2.0, Double(step))).rounded()
            return value >= Double(Int.max) ? Int.max : Int(value)
        }
    }

    /// Spoken/long form of `progressiveChain` — used as the chain row's
    /// accessibility label.
    var progressiveScalePreview: String {
        progressiveChain.enumerated()
            .map { step -> String in
                let sum = MoneyFormatter.string(step.element)
                return Localized.format("create_alarm.progressive.step", step.offset + 1, sum)
            }
            .joined(separator: " → ")
    }

    // MARK: - Available sounds (10 sounds matching Figma design)

    /// Sound catalogue surfaced to `SoundPickerViewController`. Each entry now
    /// carries a short Russian `subtitle` describing the timbre (V3 card list —
    /// `SPMore.jsx:332-339` style, e.g. «Тёплый рассвет с птицами»). The
    /// `id`/`name` members keep their existing meaning so all named-member
    /// callers (`+Sections`, list VM) compile unchanged. soundID defaults are
    /// owned by #278 — this list only adds descriptive copy.
    let availableSounds: [SoundCatalogue.Entry] = SoundCatalogue.entries

    // MARK: - System sound mapping (placeholder until custom audio files are bundled)

    /// Maps sound IDs to AudioToolbox system sound IDs for preview playback
    private static let systemSoundMap: [String: SystemSoundID] = [
        "dawn": 1005,
        "radar": 1033,
        "drops": 1006,
        "piano": 1013,
        "guitar": 1014,
        "bell": 1016,
        "waves": 1020,
        "birds": 1023,
        "classic": 1025,
        "jazz": 1026
    ]

    /// Play a preview of the given sound using system sounds.
    /// - Returns: `false` when `soundID` has no entry in `systemSoundMap` —
    ///   the tap is a no-op, which previously happened silently (#210). The
    ///   result is discardable for UI callers but lets tests pin the map
    ///   against `availableSounds` so they can't drift apart.
    @discardableResult
    func previewSound(_ soundID: String) -> Bool {
        guard let systemID = Self.systemSoundMap[soundID] else {
            AppLogger.audio.error("previewSound: unknown soundID \(soundID, privacy: .public)")
            return false
        }
        AudioServicesPlaySystemSound(systemID)
        return true
    }

    // MARK: - Alarm theme (#151)

    /// Display name of the currently selected theme. Surfaced in the
    /// `ThemeRowCell` trailing label and refreshed by the controller after
    /// the picker pops back.
    var alarmThemeName: String { theme.displayName }
}
