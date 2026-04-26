import Foundation
import AudioToolbox

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

    private let existingID: UUID?

    var isEditing: Bool { existingID != nil }

    // MARK: - Init

    init(alarm: Alarm? = nil, repository: AlarmRepository = AlarmRepository()) {
        self.alarmRepository = repository
        self.existingID = alarm?.id

        // Seed from existing alarm or defaults
        self.time = alarm?.time ?? Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date()
        self.repeatDays = alarm?.repeatDays ?? []
        self.name = alarm?.name ?? "Будильник"
        self.soundID = alarm?.soundID ?? "radar"
        self.vibrationEnabled = alarm?.vibrationEnabled ?? true
        self.snoozeMinutes = alarm?.snoozeMinutes ?? 9
        self.penaltyAmount = alarm?.penaltyAmount ?? 50
        self.progressiveScale = alarm?.progressiveScale ?? false
        self.enabled = alarm?.enabled ?? true
    }

    // MARK: - Save

    @discardableResult
    func save() -> Bool {
        let alarm = Alarm(
            id: existingID ?? UUID(),
            time: time,
            repeatDays: repeatDays,
            name: name.isEmpty ? "Будильник" : name,
            soundID: soundID,
            vibrationEnabled: vibrationEnabled,
            snoozeMinutes: snoozeMinutes,
            penaltyAmount: penaltyAmount,
            progressiveScale: progressiveScale,
            enabled: enabled
        )
        return alarmRepository.save(alarm)
    }

    // MARK: - Delete

    /// Removes the alarm being edited. Returns `false` for new (unsaved) alarms,
    /// where there is nothing to delete — the caller should treat this case as a
    /// no-op (the user can simply cancel out of the create screen instead).
    /// Cancelling the scheduled notification is handled by `AlarmRepository.delete`.
    @discardableResult
    func delete() -> Bool {
        guard let id = existingID else { return false }
        alarmRepository.delete(id: id)
        return true
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
        return values.enumerated().map { "\($0.offset + 1)-е: \($0.element)₽" }.joined(separator: " → ")
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

    /// Play a preview of the given sound using system sounds
    func previewSound(_ soundID: String) {
        guard let systemID = Self.systemSoundMap[soundID] else { return }
        AudioServicesPlaySystemSound(systemID)
    }
}
