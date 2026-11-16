import Foundation

/// Zone-free identity of a wake day — the civil calendar day the user woke
/// on, independent of whichever timezone the device reports later (#1064).
///
/// `WakeEventStore` used to persist each wake day as `Calendar.startOfDay(for:)`:
/// an absolute instant whose civil-day meaning is fixed by the timezone the
/// device had at write time. The streak, the heatmap and the savings counter
/// then rebuilt midnights in the *reader's* current timezone and compared the
/// instants for equality, so one timezone change hid every recorded morning:
/// 07:00 Europe/Moscow on 2026-10-25 stores 2026-10-24 21:00Z, while the same
/// visible morning in Asia/Dubai is 2026-10-24 20:00Z — same day on screen, no
/// set match, so the streak read 0, the heatmap cell went dark and the clean
/// morning stopped counting towards savings.
///
/// Two representations are understood here:
///
/// - **Canonical** (what the store writes from #1064 on): UTC midnight of the
///   local civil day. Its identity does not depend on any zone, so it can never
///   drift again.
/// - **Legacy** (rows written before #1064): a raw `startOfDay` in the writing
///   zone. The writing offset is recoverable from the value itself — a
///   midnight's UTC time-of-day is exactly the negative of that offset:
///   `stored = D 00:00 local = D 00:00 UTC − offset`. Real offsets span
///   −12…+14 h, which normally leaves exactly one candidate. When the stored
///   clock reads 10:00–12:00 UTC, the western (−10…−12) and eastern (+10…+14)
///   readings both fit; that window resolves east, because the app's audience
///   sits at UTC+3…UTC+12 — the west reading would mislabel more rows. Such
///   rows age out with the store's 400-day retention.
///
/// Deliberately absent: re-flooring a stored midnight into the reader's
/// timezone. That is the westbound-travel defect the issue warns about (a
/// Moscow midnight read in New York landing on the previous calendar date), and
/// it is exactly what this type exists to avoid.
struct WakeDayIdentity: Hashable, Comparable, CustomStringConvertible {

    let year: Int
    let month: Int
    let day: Int

    /// Civil day `date` falls on in `calendar`'s timezone.
    ///
    /// Used for every day the UI walks (streak step, heatmap cell, money
    /// column): each of them is a local midnight, which maps to its own
    /// year/month/day no matter what zone the reader is in.
    init(date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(
            year: components.year ?? 0,
            month: components.month ?? 0,
            day: components.day ?? 0
        )
    }

    /// The civil day a stored value was recorded for.
    ///
    /// Handles both representations described on the type; see
    /// ``init(date:calendar:)`` for the canonical side and the type docstring
    /// for the legacy reconstruction.
    init(storedDay: Date) {
        let clock = Self.utcCalendar.dateComponents([.hour, .minute], from: storedDay)
        let minutesOfDay = (clock.hour ?? 0) * 60 + (clock.minute ?? 0)

        // Offsets consistent with a stored midnight: `minutesOfDay ≡ −offset
        // (mod 24 h)`. A canonical value has `minutesOfDay == 0` and resolves
        // to 0, which is exactly what makes canonical rows reader-independent.
        let east = minutesOfDay == 0 ? 0 : 24 * 60 - minutesOfDay // [0, 24 h)
        let west = east - 24 * 60                                  // [−24 h, 0)
        let offsetMinutes = east <= Self.maxEastwardOffsetMinutes ? east : west

        // `storedDay + offset` is the civil day's UTC boundary itself, so its
        // UTC components are the identity. A DST skip at local midnight
        // (`startOfDay` landing on 01:00) shifts that boundary by an hour,
        // still inside the same day.
        let startOfCivilDay = storedDay.addingTimeInterval(Double(offsetMinutes) * 60)
        let components = Self.utcCalendar.dateComponents(
            [.year, .month, .day], from: startOfCivilDay
        )
        self.init(
            year: components.year ?? 0,
            month: components.month ?? 0,
            day: components.day ?? 0
        )
    }

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Canonical storage form: UTC midnight of this civil day. Encoding the
    /// identity as an instant keeps `wake_days` a `[Date]` blob — the same
    /// pruning and sorting as before — while removing the timezone from the
    /// value's meaning.
    var canonicalStoredDay: Date? {
        Self.utcCalendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    /// Strictest eastward offset real zones use (UTC+14, Line Islands).
    private static let maxEastwardOffsetMinutes = 14 * 60

    /// Gregorian calendar pinned to UTC — the zone stored instants are read
    /// in, never the reader's.
    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone(identifier: "GMT")!
        return calendar
    }()

    /// Chronological key — 2026-10-25 sorts after 2026-10-24.
    private var sortKey: Int { year * 10_000 + month * 100 + day }

    static func < (lhs: WakeDayIdentity, rhs: WakeDayIdentity) -> Bool {
        lhs.sortKey < rhs.sortKey
    }

    var description: String { "\(year)-\(month)-\(day)" }
}
