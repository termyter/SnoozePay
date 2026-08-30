import Foundation

/// Short Russian subtitles for the built-in alarm themes, surfaced beneath the
/// theme name in the V3 grid tiles (`SPMore2.jsx:394-400`, #285).
///
/// Kept as a pure id→key map (no UIKit) so the mapping can be unit-tested
/// and so the picker tile stays a thin layout layer. The custom-photo slot
/// gets «Из галереи» to match the design's «Своё фото · Из галереи».
enum AlarmThemeSubtitles {

    /// Catalogue key per built-in theme, keyed by `AlarmTheme.id`. The map
    /// stays an id→key table rather than an id→copy one so that an unmapped
    /// theme still returns "" — the picker tile has no room for a fallback
    /// line, and `Localized.text` would hand back the key itself.
    private static let keys: [String: String] = [
        "dawn": "create_alarm.theme.subtitle.dawn",
        "ocean": "create_alarm.theme.subtitle.ocean",
        "mountains": "create_alarm.theme.subtitle.mountains",
        "forest": "create_alarm.theme.subtitle.forest",
        "neon": "create_alarm.theme.subtitle.neon",
        "abstract": "create_alarm.theme.subtitle.abstract"
    ]

    /// Subtitle shown on the custom-photo slot tile.
    static var customSlotSubtitle: String {
        Localized.text("create_alarm.theme.subtitle.custom")
    }

    /// Subtitle for the given theme. Built-ins resolve through `keys`; the
    /// custom theme returns `customSlotSubtitle`; anything unmapped returns "".
    static func subtitle(for theme: AlarmTheme) -> String {
        if case .custom = theme { return customSlotSubtitle }
        guard let key = keys[theme.id] else { return "" }
        return Localized.text(key)
    }
}
