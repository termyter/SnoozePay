import Foundation

/// Domain model for an alarm. Separate from Core Data entity for clean MVVM.
struct Alarm: Identifiable, Equatable, Codable {
    let id: UUID
    var time: Date
    var repeatDays: [Int] // 0 = Monday, 6 = Sunday
    var name: String
    var soundID: String
    var vibrationEnabled: Bool
    var snoozeMinutes: Int
    var penaltyAmount: Double
    var progressiveScale: Bool
    var enabled: Bool

    init(
        id: UUID = UUID(),
        time: Date = Date(),
        repeatDays: [Int] = [],
        name: String = "Будильник",
        soundID: String = "radar",
        vibrationEnabled: Bool = true,
        snoozeMinutes: Int = 9,
        penaltyAmount: Double = 50,
        progressiveScale: Bool = false,
        enabled: Bool = true
    ) {
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
    }

    /// Human-readable repeat days string (e.g. "Пн, Вт, Пт")
    var repeatDaysDescription: String {
        guard !repeatDays.isEmpty else { return "Единожды" }

        let dayNames = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
        let allWeekdays = [0, 1, 2, 3, 4]
        let allWeekend = [5, 6]

        let sorted = repeatDays.sorted()

        if sorted == Array(0...6) { return "Каждый день" }
        if sorted == allWeekdays { return "Будни" }
        if sorted == allWeekend { return "Выходные" }

        return sorted.compactMap { dayNames[safe: $0] }.joined(separator: ", ")
    }

    /// Next trigger date for display purposes
    var nextTriggerDate: Date? {
        if repeatDays.isEmpty {
            let now = Date()
            return time > now ? time : nil
        }
        return time
    }

    /// Penalty for a given snooze count (1-based). Applies progressive doubling if enabled.
    func penalty(forSnoozeCount count: Int) -> Double {
        guard progressiveScale, count > 1 else { return penaltyAmount }
        let multiplier = pow(2.0, Double(count - 1))
        return penaltyAmount * multiplier
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

    /// Typed view over `repeatDays`. Out-of-range integers in legacy storage
    /// are silently skipped (existing data may contain them).
    var weekdays: Set<Weekday> {
        Set<Weekday>(legacyMondayFirstIndices: repeatDays)
    }

    /// Typed view of `penaltyAmount`. `nil` if the legacy `Double` is
    /// negative or non-finite, which a typed setter would have refused.
    var penaltyMoney: Money? {
        Money(penaltyAmount)
    }
}

// MARK: - Safe array subscript
private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
