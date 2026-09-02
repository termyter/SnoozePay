import Foundation

/// Static source of truth for the alarm-sound catalogue surfaced in the V3
/// sound picker (`SoundPickerViewController`, #285).
///
/// The design (`SPMore.jsx:330-409`) renders each sound as a card row with a
/// descriptive Russian subtitle («Тёплый рассвет с птицами» style) plus a
/// trailing «Своя мелодия · скоро» slot that is visually present but disabled
/// until custom-import ships. Keeping this as a plain value type (no UIKit)
/// lets the subtitle/catalogue mapping be unit-tested without a simulator —
/// the pure-logic split the issue calls for.
///
/// `CreateAlarmViewModel.availableSounds` is derived from `entries`, so the
/// 10-sound catalogue stays the single source of truth; the picker pulls the
/// disabled custom slot from `customSlot`.
///
/// # Where the copy lives (#598)
///
/// Ids are code, words are catalogue: this type stores the ten ids and reads
/// every name and subtitle out of `Localizable.xcstrings`. Two namespaces,
/// because the two columns of a row have different reach and the convention in
/// ``Localized`` keys on reach rather than on origin:
///
/// | column | keys | seen on |
/// |---|---|---|
/// | name | `common.sound.name.<id>` | picker row **and** alarms-list cell |
/// | subtitle | `create_alarm.sound.subtitle.<id>` | picker row only |
///
/// The names are the shared half, so `AlarmsListViewModel.soundDisplayNames`
/// — ten literals duplicating this list, deliberately left behind by #599 —
/// collapses onto `Localized.text(nameKey(for:))` rather than onto a second
/// set of keys for the same ten words. That call site is not touched here, and
/// neither is an accessor minted for it in advance: this slice owns the keys,
/// #599 owns the reader.
enum SoundCatalogue {

    /// One selectable sound. `subtitle` is the V3 descriptive copy.
    struct Entry: Equatable {
        let id: String
        let name: String
        let subtitle: String
    }

    /// The 10 system sounds, in catalogue order. IDs match the pre-V3
    /// `availableSounds` list (do NOT cut to 6 — design keeps the full
    /// lineup).
    static let ids: [String] = [
        "dawn", "radar", "drops", "piano", "guitar",
        "bell", "waves", "birds", "classic", "jazz"
    ]

    /// Id of the disabled custom-melody slot. Not one of ``ids``: it is
    /// rendered after the catalogue and cannot be selected.
    static let customSlotID = "custom"

    /// Catalogue key holding the display name of a sound in ``ids``.
    ///
    /// Exposed rather than inlined so that a test can assert a call site reads
    /// *this* key, and so #599 has one place to point at instead of guessing
    /// the spelling — this is the whole seam that lane needs. The custom slot
    /// is not covered: it is picker-only copy and names its keys inline in
    /// ``customSlot``.
    static func nameKey(for soundID: String) -> String {
        "common.sound.name.\(soundID)"
    }

    /// Catalogue key holding the descriptive subtitle of a sound in ``ids``.
    static func subtitleKey(for soundID: String) -> String {
        "create_alarm.sound.subtitle.\(soundID)"
    }

    /// The 10 system sounds, in catalogue order.
    ///
    /// Computed rather than stored so the catalogue read stays behind
    /// ``Localized`` — the single seam #596 has to move when the app stops
    /// declaring English and shipping Russian. It is not a language-switch
    /// affordance: `AppLocale.display` is hardcoded `ru_RU` and
    /// `Localized.bundle` resolves once per process, so nothing below this
    /// property can change language at runtime today. Callers that render in a
    /// loop hold the result (`CreateAlarmViewModel.availableSounds`,
    /// `SoundPickerViewController.sounds`) instead of re-reading it per cell.
    static var entries: [Entry] {
        ids.map { soundID in
            Entry(
                id: soundID,
                name: Localized.text(nameKey(for: soundID)),
                subtitle: Localized.text(subtitleKey(for: soundID))
            )
        }
    }

    /// Disabled trailing slot rendered after the catalogue. Custom-melody
    /// import is out of scope here, so the row is non-interactive.
    ///
    /// The picker wraps the name in `create_alarm.sound_picker.custom_slot`
    /// («%@ · скоро») and substitutes its own subtitle, so `subtitle` here
    /// reaches no screen today; it stays because a blank column would be a
    /// behaviour change to a shared value type, not a string move.
    static var customSlot: Entry {
        Entry(
            id: customSlotID,
            name: Localized.text("create_alarm.sound.name.custom"),
            subtitle: Localized.text("create_alarm.sound.subtitle.custom")
        )
    }

    /// Subtitle for a given sound id, or `nil` when the id isn't catalogued.
    ///
    /// The picker reads subtitles off ``entries`` rather than through here —
    /// it renders whole rows — so this is the lookup for a caller holding only
    /// an id.
    static func subtitle(for soundID: String) -> String? {
        guard ids.contains(soundID) else { return nil }
        return Localized.text(subtitleKey(for: soundID))
    }
}
