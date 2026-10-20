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
/// # Resource resolution
///
/// `AlarmButton(text:)` and `AppIntent.title` both take a
/// `LocalizedStringResource`, but their values are prepared differently.
///
/// The alert's **secondary button** is built at schedule time. Its price is
/// already formatted, so ``pricedSnoozeTitle(penalty:)`` resolves the current
/// app-language catalogue entry before handing the complete words to AlarmKit.
/// Already scheduled presentation text is not relocalized by this helper.
///
/// The two **intent titles** are exported at build time. They use literal,
/// statically extractable keys with table `Localizable` and the main bundle;
/// a runtime `Localized.text` call or an alternate bundle cannot be exported.
/// The compiled RU and EN tables support these lookups independently of the
/// app's `Localized.bundle` selection. Shortcuts and Siri can resolve the
/// resources in a different locale from the app's UI language.
/// `AlarmKitCopyTests` renders the actual intent resources in both languages;
/// physical system-surface acceptance remains part of #727.
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

    /// The catalogue key used by `StopAlarmIntent.title`, the intent name
    /// shown in Shortcuts and Siri, rather than a system stop-button label.
    static let stopKey = "alarm_kit.action.stop"

    /// The catalogue key used by `SnoozeAlarmIntent.title`. The alert's
    /// secondary button has its own priced label, ``pricedSnoozeKey``.
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
