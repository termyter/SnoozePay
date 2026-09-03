import Foundation

/// The three strings the app hands to AlarmKit and AppIntents for a ringing
/// alarm (#723).
///
/// Exactly one of them is a button whose text we set: the alert's secondary
/// button, via `AlarmButton(text:)`. The other two are *intent titles*, which
/// AppIntents publishes as the names of `StopAlarmIntent` / `SnoozeAlarmIntent`
/// — Shortcuts and Siri show them. Whether the system also paints the stop
/// intent's title on the alert is **not** something this repository or the SDK
/// establishes: `AlarmPresentation.Alert.stopButton` is deprecated in
/// iOS 26.1 as "not used anymore", and `AlarmKitScheduler` uses the 26.1
/// initializer that has no stop button at all. So we configure no stop button
/// text; what the alert renders for stopping is the system's business.
///
/// # Why these three strings sat outside the catalogue
///
/// `AlarmButton(text:)` and `AppIntent.title` take a `LocalizedStringResource`,
/// not a `String`, so these call sites cannot read ``Localized/text(_:)``
/// inline the way every screen in the app does. They therefore carried Russian
/// literals — and a `LocalizedStringResource` built from a literal uses that
/// literal as its **key**: the runtime looks the key up, misses, and hands the
/// literal back.
///
/// It misses for two independent reasons, and both survive translation:
///
///  1. The catalogue is keyed by symbolic keys (`firing.action.snooze`), not by
///     the Russian words that are its *values*. A lookup for «Поспать ещё»
///     matches nothing, however many entries hold those words. (No key in the
///     catalogue contains a non-ASCII character, so this holds for all 396.)
///  2. `knownRegions` is `(en, Base)` (#596), so on a device whose preferred
///     language is anything but Russian `Bundle.main` negotiates to
///     `Base.lproj`, which holds no copy at all — see ``Localized``. (A
///     Russian device probably does reach `ru.lproj` through `.main`; the
///     app cannot rely on that, which is why ``Localized`` opens the bundle
///     itself.)
///
/// So the words shipped from Swift, by fallback, invisible to the catalogue and
/// to every test in the suite.
///
/// # What moved, and what could not
///
/// The alert's **secondary button** is an ordinary `AlarmButton` built at
/// schedule time, so ``pricedSnoozeTitle(penalty:)`` reads the catalogue and
/// hands the resolved words on as a resource via
/// `LocalizedStringResource(stringLiteral:)` — the idiom `AlarmKitScheduler`
/// already uses for the alarm's own name. The rendered text is now the
/// catalogue value, byte-for-byte the literal that shipped before.
///
/// The two **intent titles** could not move, and the reason is structural
/// rather than a matter of finding the right spelling. AppIntents exports them
/// at build time via `appintentsmetadataprocessor`, which rejects any value it
/// cannot extract statically *and* rejects every bundle but the main one — the
/// one bundle this app's copy is unreachable through until #596. The four
/// spellings and the processor's verbatim answers are recorded on
/// `StopAlarmIntent.title`; the follow-up is #727.
///
/// Their words still live here, under ``stopKey`` and ``snoozeKey``, and
/// `AlarmKitCopyTests` fails if the literals and those entries stop agreeing.
/// That is weaker than migrating them — the literal is still what renders —
/// but it is what stops the two surfaces from drifting apart silently, which
/// is the failure #723 was opened for.
///
/// # Why the keys are their own `alarm_kit.*` domain
///
/// ``Localized`` names a domain after the screen the copy is seen on, and none
/// of these three has one. Two are intent names, shown wherever the system
/// lists intents; the third is a button on a presentation the system renders
/// where it chooses. What they share is not a screen but a mechanism — they
/// are the strings this app hands to AlarmKit for a ringing alarm — so the
/// mechanism gets the domain. The per-key `comment` in the catalogue records
/// why each one is not merged with the similarly-worded key next door.
enum AlarmKitCopy {

    // MARK: - Keys

    /// «Выключить будильник» — the words `StopAlarmIntent.title` carries, and
    /// so the name Shortcuts shows for that intent. Read by the test that pins
    /// the literal, not yet by the intent itself.
    static let stopKey = "alarm_kit.action.stop"

    /// «Поспать ещё» — the name Shortcuts shows for `SnoozeAlarmIntent`, under
    /// the same pinned-but-not-yet-read arrangement as ``stopKey``. Not the
    /// text of the alert's snooze button: that is ``pricedSnoozeKey``.
    static let snoozeKey = "alarm_kit.action.snooze"

    /// «Поспать ещё (−50 ₽)» — the text of the alert's secondary button, which
    /// names the price. `%@` is a sum already formatted by ``MoneyFormatter``.
    /// The only one of the three whose surface is ours to set, and the only
    /// one read at runtime.
    static let pricedSnoozeKey = "alarm_kit.action.snooze.priced"

    // MARK: - Copy

    /// The secondary button's label for a snooze that costs `penalty`.
    ///
    /// The sum is substituted into the catalogue's format rather than
    /// concatenated, because where the price sits inside the phrase is a
    /// property of the language — the same rule ``Localized`` states for
    /// `firing.hint.next_price`.
    static func pricedSnooze(penalty: Double) -> String {
        Localized.format(pricedSnoozeKey, MoneyFormatter.string(penalty))
    }

    static func pricedSnoozeTitle(penalty: Double) -> LocalizedStringResource {
        LocalizedStringResource(stringLiteral: pricedSnooze(penalty: penalty))
    }
}
