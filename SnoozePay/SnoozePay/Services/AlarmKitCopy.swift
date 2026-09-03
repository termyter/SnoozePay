import Foundation

/// The words on the buttons iOS renders while an alarm rings — the AlarmKit
/// alert on the lock screen, in the Dynamic Island and as a banner (#723).
///
/// # Why these three strings needed their own type
///
/// `AlarmButton(text:)` and `AppIntent.title` take a `LocalizedStringResource`,
/// not a `String`, so these call sites cannot read ``Localized/text(_:)``
/// inline the way every screen in the app does. Until #723 they therefore
/// carried Russian literals — and a `LocalizedStringResource` built from a
/// literal uses that literal as its **key**: the runtime looks the key up,
/// misses, and hands the literal back.
///
/// It misses for two independent reasons, and both survive translation:
///
///  1. The catalogue is keyed by symbolic keys (`firing.action.snooze`), not by
///     the Russian words that are its *values*. A lookup for «Поспать ещё»
///     matches nothing, however many entries hold those words.
///  2. `knownRegions` is `(en, Base)` (#596), so `Bundle.main` negotiates to
///     `Base.lproj`, which holds no copy at all — see ``Localized``.
///
/// So the words shipped from Swift, by fallback, invisible to the catalogue and
/// to every test in the suite. Adding a second language would have left the
/// loudest copy in the app — the buttons a half-awake user taps at 7am —
/// stubbornly Russian, with nothing going red.
///
/// # What this type does instead
///
/// It reads the words out of the catalogue like everything else, and hands the
/// resolved `String` on as a resource via `LocalizedStringResource(stringLiteral:)`
/// — the idiom `AlarmKitScheduler` already uses for the alarm's own name. The
/// resource therefore still carries words rather than a key, which is what
/// makes the change a move rather than a behaviour change: the rendered text is
/// the catalogue value, and the catalogue values are byte-for-byte the literals
/// that shipped before.
///
/// Passing the key straight through (`LocalizedStringResource("alarm_kit.action.stop")`)
/// would read better and is what the issue sketched, but it resolves against
/// `Bundle.main` — reason 2 above — so the lock-screen button would read
/// `alarm_kit.action.stop`. That collapses to the obvious spelling on the day
/// #596 fixes `knownRegions`, and not before.
///
/// # Why the keys are their own `alarm_kit.*` domain
///
/// ``Localized`` names a domain after the screen the copy is seen on, and this
/// copy has no single screen: the same three strings surface on the lock
/// screen, in the Dynamic Island and in a banner, all rendered by the system
/// from one `AlarmPresentation`. The shared area is that presentation, so it
/// gets the domain. The per-key `comment` in the catalogue records why each one
/// is not merged with the similarly-worded key next door.
enum AlarmKitCopy {

    // MARK: - Keys

    /// «Выключить будильник» — `StopAlarmIntent.title`.
    static let stopKey = "alarm_kit.action.stop"

    /// «Поспать ещё» — `SnoozeAlarmIntent.title`.
    static let snoozeKey = "alarm_kit.action.snooze"

    /// «Поспать ещё (−50 ₽)» — the alert's secondary button, which names the
    /// price. `%@` is a sum already formatted by ``MoneyFormatter``.
    static let pricedSnoozeKey = "alarm_kit.action.snooze.priced"

    // MARK: - Copy

    static var stop: String {
        Localized.text(stopKey)
    }

    static var snooze: String {
        Localized.text(snoozeKey)
    }

    /// The secondary button's label for a snooze that costs `penalty`.
    ///
    /// The sum is substituted into the catalogue's format rather than
    /// concatenated, because where the price sits inside the phrase is a
    /// property of the language — the same rule ``Localized`` states for
    /// `firing.hint.next_price`.
    static func pricedSnooze(penalty: Double) -> String {
        Localized.format(pricedSnoozeKey, MoneyFormatter.string(penalty))
    }

    // MARK: - Resources for the AlarmKit / AppIntents call sites

    static var stopTitle: LocalizedStringResource {
        LocalizedStringResource(stringLiteral: stop)
    }

    static var snoozeTitle: LocalizedStringResource {
        LocalizedStringResource(stringLiteral: snooze)
    }

    static func pricedSnoozeTitle(penalty: Double) -> LocalizedStringResource {
        LocalizedStringResource(stringLiteral: pricedSnooze(penalty: penalty))
    }
}
