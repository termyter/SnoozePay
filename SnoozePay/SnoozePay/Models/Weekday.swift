import Foundation

/// Day of the week, aligned with `Calendar.weekday` (1 = Sunday … 7 = Saturday).
///
/// This matches `DateComponents.weekday` and `UNCalendarNotificationTrigger`'s
/// expected values directly, so scheduling code can pass `rawValue` without
/// any off-by-one bridging.
///
/// The legacy storage on `Alarm.repeatDays: [Int]` uses a *different*
/// convention (0 = Monday … 6 = Sunday). The `init?(legacyMondayFirstIndex:)`
/// initializer and the `legacyMondayFirstIndex` property bridge between the
/// two so we can introduce typed access without rewriting persisted JSON.
enum Weekday: Int, CaseIterable, Codable, Hashable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7

    // MARK: - Legacy bridge (Mon=0 … Sun=6)

    /// Build from the project's legacy `repeatDays` integer convention
    /// (0 = Monday … 6 = Sunday). Returns `nil` for any value outside `0...6`,
    /// which were silently allowed before this type existed.
    init?(legacyMondayFirstIndex index: Int) {
        switch index {
        case 0: self = .monday
        case 1: self = .tuesday
        case 2: self = .wednesday
        case 3: self = .thursday
        case 4: self = .friday
        case 5: self = .saturday
        case 6: self = .sunday
        default: return nil
        }
    }

    /// The legacy index (0 = Monday … 6 = Sunday) for round-tripping
    /// back into the existing `[Int]` storage.
    var legacyMondayFirstIndex: Int {
        switch self {
        case .monday: return 0
        case .tuesday: return 1
        case .wednesday: return 2
        case .thursday: return 3
        case .friday: return 4
        case .saturday: return 5
        case .sunday: return 6
        }
    }

    // MARK: - Display

    /// Short label from the string catalogue, matching the existing UI strings
    /// on `Alarm.repeatDaysDescription` ("Пн, Вт, …").
    ///
    /// The keys are spelled out per case rather than interpolated from a
    /// suffix so that `git grep common.weekday.short` finds every one of them
    /// — a catalogue key is an ordinary `String`, and an interpolated one is
    /// invisible to every tool the project has.
    var localizedShortName: String {
        switch self {
        case .monday: return Localized.text("common.weekday.short.mon")
        case .tuesday: return Localized.text("common.weekday.short.tue")
        case .wednesday: return Localized.text("common.weekday.short.wed")
        case .thursday: return Localized.text("common.weekday.short.thu")
        case .friday: return Localized.text("common.weekday.short.fri")
        case .saturday: return Localized.text("common.weekday.short.sat")
        case .sunday: return Localized.text("common.weekday.short.sun")
        }
    }
}

// MARK: - Convenience: convert a legacy `[Int]` set into a typed `Set<Weekday>`

extension Set where Element == Weekday {

    /// Convert from the project's legacy `repeatDays: [Int]` storage. Silently
    /// drops any out-of-range integers (the legacy storage allowed them; the
    /// typed view skips them rather than crashing existing user data).
    init(legacyMondayFirstIndices indices: [Int]) {
        self.init(indices.compactMap { Weekday(legacyMondayFirstIndex: $0) })
    }

    /// Round-trip back to the legacy `[Int]` storage, sorted Mon→Sun.
    var legacyMondayFirstIndices: [Int] {
        map(\.legacyMondayFirstIndex).sorted()
    }
}
