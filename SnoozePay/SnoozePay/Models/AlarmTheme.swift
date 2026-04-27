import Foundation

/// Visual theme applied to an alarm's card preview and firing screen (#151).
///
/// The five built-in cases are gradient-only so they ship without bundled
/// imagery; `.custom` carries an absolute file URL for a user-picked photo
/// stored in the app's Caches directory by `AlarmThemeImageStore`.
///
/// Codable is hand-rolled because Swift's synthesized representation for
/// enums-with-associated-values pulls in Apple's `_$s…` type wrappers that
/// surface as tagged JSON keys. Keeping the encoded form flat (`{"id": "dawn"}`
/// or `{"id": "custom", "imagePath": "/var/.../IMG.jpg"}`) lets us migrate the
/// model on disk in #151 without re-encoding every existing alarm.
enum AlarmTheme: Equatable {
    case dawn
    case mountains
    case ocean
    case abstract
    case custom(imagePath: URL)

    // MARK: - Identity

    /// Stable string identifier used in JSON storage and as an
    /// `Equatable`-friendly key for collection views.
    var id: String {
        switch self {
        case .dawn: return "dawn"
        case .mountains: return "mountains"
        case .ocean: return "ocean"
        case .abstract: return "abstract"
        case .custom: return "custom"
        }
    }

    // MARK: - Display

    /// Russian display name surfaced in the picker tile and the create-form
    /// trailing label.
    var displayName: String {
        switch self {
        case .dawn: return "Рассвет"
        case .mountains: return "Горы"
        case .ocean: return "Океан"
        case .abstract: return "Абстракция"
        case .custom: return "Своё фото"
        }
    }

    /// Built-in (non-custom) themes in their canonical picker order. The
    /// `.custom` tile is appended separately by the picker view-controller so
    /// the "+" affordance always reads as the trailing slot.
    static let builtInOrder: [AlarmTheme] = [.dawn, .mountains, .ocean, .abstract]
}

// MARK: - Codable

extension AlarmTheme: Codable {

    private enum CodingKeys: String, CodingKey {
        case id
        case imagePath
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        switch id {
        case "dawn": self = .dawn
        case "mountains": self = .mountains
        case "ocean": self = .ocean
        case "abstract": self = .abstract
        case "custom":
            // Path stored as a string so the JSON stays portable across
            // app reinstalls (URLs round-trip cleanly via init(string:)).
            // If the path is missing we degrade to `.dawn` rather than
            // throwing — a corrupt theme should not block the alarm decode.
            if let raw = try container.decodeIfPresent(String.self, forKey: .imagePath),
               let url = URL(string: raw) {
                self = .custom(imagePath: url)
            } else {
                self = .dawn
            }
        default:
            // Forward-compat: an unknown theme id (added by a newer build)
            // degrades silently to the default rather than throwing — the
            // old build would otherwise refuse to decode the alarm at all.
            self = .dawn
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        if case .custom(let url) = self {
            try container.encode(url.absoluteString, forKey: .imagePath)
        }
    }
}
