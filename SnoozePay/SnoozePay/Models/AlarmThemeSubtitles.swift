import Foundation

/// Short Russian subtitles for the built-in alarm themes, surfaced beneath the
/// theme name in the V3 grid tiles (`SPMore2.jsx:394-400`, #285).
///
/// Kept as a pure id→subtitle map (no UIKit) so the mapping can be unit-tested
/// and so the picker tile stays a thin layout layer. The custom-photo slot
/// gets «Из галереи» to match the design's «Своё фото · Из галереи».
enum AlarmThemeSubtitles {

    /// Built-in theme subtitles, keyed by `AlarmTheme.id`. Derived from the
    /// design's per-theme copy (dawn «Тёплый янтарь», ocean «Холодный мятный»…).
    private static let map: [String: String] = [
        "dawn": "Тёплый янтарь",
        "ocean": "Холодный мятный",
        "mountains": "Молочный свет",
        "forest": "Хвойный сумрак",
        "neon": "Городская ночь",
        "abstract": "Чистый цвет"
    ]

    /// Subtitle shown on the custom-photo slot tile.
    static let customSlotSubtitle = "Из галереи"

    /// Subtitle for the given theme. Built-ins resolve from `map`; the custom
    /// theme returns `customSlotSubtitle`; anything unmapped returns "".
    static func subtitle(for theme: AlarmTheme) -> String {
        if case .custom = theme { return customSlotSubtitle }
        return map[theme.id] ?? ""
    }
}
