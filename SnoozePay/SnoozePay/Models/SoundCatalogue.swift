import AVFoundation
import Foundation
import os

/// Static source of truth for the alarm-sound catalogue surfaced in the V3
/// sound picker (`SoundPickerViewController`, #285).
///
/// The design (`SoundPicker()`,
/// `docs/design/snoozepay-2026-04-27/project/components/SPMore.jsx:294-374` contains "function SoundPicker")
/// renders each sound as a card row with a
/// descriptive Russian subtitle («Тёплый рассвет с птицами» style) plus a
/// trailing «Своя мелодия · скоро» slot that is visually present but disabled
/// until custom-import ships. Keeping this as a plain value type (no UIKit)
/// lets the subtitle/catalogue mapping be unit-tested without a simulator —
/// the pure-logic split the issue calls for.
///
/// `CreateAlarmViewModel.availableSounds` is derived from `entries`, so the
/// 14-sound catalogue stays the single source of truth; the picker pulls the
/// disabled custom slot from `customSlot`.
///
/// # Where the copy lives (#598)
///
/// Ids are code, words are catalogue: this type stores the ids and reads
/// every name and subtitle out of `Localizable.xcstrings`. Two namespaces,
/// because the two columns of a row have different reach and the convention in
/// ``Localized`` keys on reach rather than on origin:
///
/// | column | keys | seen on |
/// |---|---|---|
/// | name | `common.sound.name.<id>` | picker row **and** alarms-list cell |
/// | subtitle | `create_alarm.sound.subtitle.<id>` | picker row only |
///
/// The names are the shared half, and both readers now resolve them through
/// ``nameKey(for:)``: this type for the picker row, and
/// `AlarmsListViewModel.alarmSoundName(at:)` for the alarms-list cell, whose
/// ten duplicate literals #599 deleted rather than giving a second set of keys
/// to the same ten words. The list VM reads the key through
/// ``Localized/optionalText(_:)`` and not ``Localized/text(_:)`` because its
/// documented miss behaviour is to render the raw sound id; see that method.
enum SoundCatalogue {

    /// One selectable sound. `subtitle` is the V3 descriptive copy.
    struct Entry: Equatable {
        let id: String
        let name: String
        let subtitle: String
    }

    /// The 14 bundled sounds, in catalogue order. The first ten match the
    /// pre-V3 `availableSounds` list (do NOT cut to 6 — design keeps the full
    /// lineup); `hawk`, `morning`, `sirena` and `spaceship` are the PM's
    /// recordings appended by #850. Each id is also the base name of its file
    /// in `Resources/Sounds/`, which is how both the ring and the preview
    /// find it (``fileURL(for:resourceURL:)``).
    ///
    /// The order is the picker's row order and is pinned to a literal copy of
    /// this list in `SoundCatalogueCopyTests.idsInCatalogueOrder` (#762), so
    /// reordering or extending it costs a red run there on purpose. Before
    /// #762 the prose above was the only thing saying so, and `ids.sort()` was
    /// green across the target.
    static let ids: [String] = [
        "dawn", "radar", "drops", "piano", "guitar",
        "bell", "waves", "birds", "classic", "jazz",
        "hawk", "morning", "sirena", "spaceship"
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

    /// The catalogue sounds, in catalogue order.
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

    /// Bundled file behind a sound id, probed exactly as the ring probes it:
    /// `<id>` across `AudioService.alarmSoundExtensions`, via
    /// `AudioService.firstBundledURL(for:resourceURL:)`. `nil` when the bundle
    /// has no such file — unlike the ring there is no `default_alarm`
    /// fallback, because a preview of another sound under this row's name
    /// would hide the gap instead of showing it.
    ///
    /// An empty id is a miss up front: `Bundle.url(forResource:withExtension:)`
    /// reads an empty name as "any file", and would hand back the first `.caf`.
    ///
    /// `resourceURL` lets a test state which files the bundle holds; the
    /// default is the real bundle, which in the test host is the app's.
    static func fileURL(
        for soundID: String,
        resourceURL: (String, String) -> URL? = { name, ext in
            Bundle.main.url(forResource: name, withExtension: ext)
        }
    ) -> URL? {
        guard !soundID.isEmpty else { return nil }
        return AudioService.firstBundledURL(for: soundID, resourceURL: resourceURL)
    }

    /// Log identifier for a bundled sound file whose header cannot be read.
    static var durationUnreadableErrorID: String { "PREVIEW-850-DURATION-UNREADABLE" }

    /// Length in seconds of the file ``fileURL(for:resourceURL:)`` finds, read
    /// from its header — the preview rail in `SoundPickerViewController` runs
    /// for exactly this long (#850; it used to be a hand-written table that
    /// reset `spaceship`'s 25.8 s after 3 s). `nil` when there is no file or
    /// it cannot be opened; the second case is logged, since a file that is
    /// there but unreadable is a broken build, not an unknown id.
    static func fileDuration(for soundID: String) -> TimeInterval? {
        guard let url = fileURL(for: soundID) else { return nil }
        do {
            let file = try AVAudioFile(forReading: url)
            guard file.fileFormat.sampleRate > 0 else { return nil }
            return Double(file.length) / file.fileFormat.sampleRate
        } catch {
            AppLogger.emit(
                .audio, .error,
                "[\(durationUnreadableErrorID)] \(url.lastPathComponent): \(error.localizedDescription)"
            )
            return nil
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
}
