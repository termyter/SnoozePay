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
enum SoundCatalogue {

    /// One selectable sound. `subtitle` is the V3 descriptive copy.
    struct Entry: Equatable {
        let id: String
        let name: String
        let subtitle: String
    }

    /// The 10 system sounds, in catalogue order. IDs and display names match
    /// the pre-V3 `availableSounds` list (do NOT cut to 6 — design keeps the
    /// full lineup); only the descriptive subtitles are new.
    static let entries: [Entry] = [
        Entry(id: "dawn", name: "Рассвет", subtitle: "Тёплый рассвет с птицами"),
        Entry(id: "radar", name: "Радар", subtitle: "Нарастающий сигнал тревоги"),
        Entry(id: "drops", name: "Капли", subtitle: "Мягкие капли воды"),
        Entry(id: "piano", name: "Пиано", subtitle: "Спокойные клавиши"),
        Entry(id: "guitar", name: "Гитара", subtitle: "Лёгкий струнный перебор"),
        Entry(id: "bell", name: "Колокольчик", subtitle: "Чистый звон без музыки"),
        Entry(id: "waves", name: "Волны", subtitle: "Прибой и морской бриз"),
        Entry(id: "birds", name: "Птицы", subtitle: "Только щебет, без музыки"),
        Entry(id: "classic", name: "Классика", subtitle: "Старый добрый писк"),
        Entry(id: "jazz", name: "Джаз", subtitle: "Бодрое утреннее настроение")
    ]

    /// Disabled trailing slot rendered after the catalogue. Custom-melody
    /// import is out of scope here, so the row reads «Своя мелодия · скоро»
    /// and is non-interactive (matches the design's «Своя мелодия» slot).
    static let customSlot = Entry(
        id: "custom",
        name: "Своя мелодия",
        subtitle: "Скоро"
    )

    /// Subtitle for a given sound id, or `nil` when the id isn't catalogued.
    /// Used by the picker to keep subtitle wiring data-driven.
    static func subtitle(for soundID: String) -> String? {
        entries.first(where: { $0.id == soundID })?.subtitle
    }
}
