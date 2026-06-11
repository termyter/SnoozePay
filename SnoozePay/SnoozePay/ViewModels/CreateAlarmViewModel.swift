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

    private let existingID: UUID?

    var isEditing: Bool { existingID != nil }

    // MARK: - Init

    /// Allowed range for `snoozeMinutes`. The form's slider exposes 1...15 only
    /// (#143); editing legacy alarms persisted with values outside that range
    /// must clamp on load so the slider can render the value without crashing.
    static let snoozeMinutesRange: ClosedRange<Int> = 1...15

    init(alarm: Alarm? = nil, repository: AlarmRepository = .shared) {
        self.alarmRepository = repository
        self.existingID = alarm?.id

        // Seed from existing alarm or defaults
        self.time = alarm?.time ?? Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date()
        self.repeatDays = alarm?.repeatDays ?? []
        self.name = alarm?.name ?? "Будильник"
        self.soundID = alarm?.soundID ?? "radar"
        self.vibrationEnabled = alarm?.vibrationEnabled ?? true
        // Clamp legacy values silently — pre-#143 alarms could store up to 30
        // minutes (old stepper range). The form's slider now caps at 15.
        let rawSnooze = alarm?.snoozeMinutes ?? 9
        self.snoozeMinutes = min(max(rawSnooze, Self.snoozeMinutesRange.lowerBound), Self.snoozeMinutesRange.upperBound)
        self.penaltyAmount = alarm?.penaltyAmount ?? 50
        self.progressiveScale = alarm?.progressiveScale ?? false
        self.enabled = alarm?.enabled ?? true
        self.volume = alarm?.volume ?? 1.0
        self.volumeFadeIn = alarm?.volumeFadeIn ?? false
        self.theme = alarm?.theme ?? .dawn
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
            theme: theme
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

    var progressiveScalePreview: String {
        let base = Int(penaltyAmount)
        let values = (0..<4).map { base * Int(pow(2.0, Double($0))) }
        return values.enumerated()
            .map { "\($0.offset + 1)-е: \(MoneyFormatter.string($0.element))" }
            .joined(separator: " → ")
    }

    // MARK: - Available sounds (10 sounds matching Figma design)

    let availableSounds: [(id: String, name: String)] = [
        ("dawn", "Рассвет"),
        ("radar", "Радар"),
        ("drops", "Капли"),
        ("piano", "Пиано"),
        ("guitar", "Гитара"),
        ("bell", "Колокольчик"),
        ("waves", "Волны"),
        ("birds", "Птицы"),
        ("classic", "Классика"),
        ("jazz", "Джаз")
    ]

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
