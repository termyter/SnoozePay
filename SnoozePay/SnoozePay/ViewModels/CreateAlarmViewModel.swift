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
        self.repeatDays = alarm?.repeatDays ?? []
        // New alarms start with an empty name so the form shows the
        // "Название" placeholder (#231); `makeAlarmFromCurrentState` falls
        // back to "Будильник" when the user saves without typing one.
        self.name = alarm?.name ?? ""
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
        self.repeatMode = alarm?.repeatMode ?? .weekly
    }

    // MARK: - Save

    /// Outcome of `save()` reported to the view-controller.
    /// `persistFailed` mirrors the original `false` return from #72 — the
    /// store rejected the write (locked / encode error). `schedulingFailed`
    /// is the new failure path from #118 — persistence succeeded but the
    /// notification request itself didn't register, which historically
    /// surfaced as a fake "Будильник создан" toast on a silently dropped
    /// alarm.
    enum SaveOutcome: Equatable {
        case success
        case persistFailed
        case schedulingFailed(AlarmScheduler.SchedulingError)
    }

    /// Save the alarm and report the outcome asynchronously.
    /// Persistence is synchronous, so `.persistFailed` resolves on the
    /// caller's queue; the schedule branch resolves on main once the
    /// notification request lands or fails (issue #118).
    /// The repository contract guarantees `schedulingResult` only fires on
    /// the successful-persist path, so we never deliver two outcomes.
    func save(completion: @escaping (SaveOutcome) -> Void) {
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
    @discardableResult
    func save() -> Bool {
        alarmRepository.save(makeAlarmFromCurrentState())
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
            name: name.isEmpty ? "Будильник" : name,
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
    var repeatModeHint: String {
        switch repeatMode {
        case .never:
            return "Будильник сработает в выбранные дни один раз и отключится."
        case .weekly:
            return "Будет повторяться каждую неделю по выбранным дням."
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
    /// matches the canonical charge engine `Alarm.penalty(forSnoozeCount:)`
    /// exactly on fractional bases (e.g. 49.5 ₽ → 49.5/99/198/396, not the
    /// truncate-then-shift 49/98/196/392 of the old `Int << $0`). The final
    /// `Int` conversion is clamped to avoid trapping on an absurdly large
    /// penalty — `PenaltyCell` enforces only a minimum, no upper bound (#373).
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
            .map { "\($0.offset + 1)-е: \(MoneyFormatter.string($0.element))" }
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
