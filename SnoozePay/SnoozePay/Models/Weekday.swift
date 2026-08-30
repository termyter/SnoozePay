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

    /// Short label for ``AppLocale/display``, Monday-first: «Пн», «Вт», …
    ///
    /// Calendar data, not copy (#569): the names come from CLDR through
    /// ``WeekdayNames/short`` rather than from `Localizable.xcstrings`. Asking
    /// a translator for them would mean retyping a table every locale already
    /// ships — and, the reason it matters here rather than being a matter of
    /// taste, the alarm card renders `AlarmsListViewModel.weekdayPhrase` and
    /// `Alarm.repeatDaysDescription` side by side. The first has always read
    /// CLDR; a catalogue copy behind the second would let the two halves of a
    /// single card disagree the moment a second language exists.
    ///
    /// Copy that *contains* a weekday («Будни · Пн–Пт») is the opposite case
    /// and stays whole in the catalogue, per ``WeekdayNames``.
    var localizedShortName: String {
        // `mondayFirst(_:)` yields [] when Foundation hands back anything but
        // seven symbols, so this cannot index blindly.
        let names = WeekdayNames.short
        return names.indices.contains(legacyMondayFirstIndex) ? names[legacyMondayFirstIndex] : ""
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
