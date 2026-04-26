import UIKit

/// Owns the user's preferred interface theme and applies it to the active
/// window scene. Keeps `preferred_theme` UserDefaults persistence in one place
/// so SettingsVC, SceneDelegate, and any future caller don't reimplement the
/// "string -> UIUserInterfaceStyle" mapping (and miss a window when iterating).
final class ThemeService {

    static let shared = ThemeService()

    /// Stable string IDs persisted in UserDefaults. Add new cases by extending
    /// the enum — `from(rawValue:)` falls back to `.system` for unknown values
    /// so older builds reading future values don't crash.
    enum Theme: String, CaseIterable {
        case system
        case light
        case dark

        var interfaceStyle: UIUserInterfaceStyle {
            switch self {
            case .system: return .unspecified
            case .light: return .light
            case .dark: return .dark
            }
        }
    }

    // MARK: - Storage

    private let defaults: UserDefaults
    private let themeKey = "preferred_theme"

    /// Production code MUST use `ThemeService.shared`. Direct construction is
    /// allowed in tests so each test can inject an isolated UserDefaults suite.
    #if DEBUG
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
    #else
    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
    #endif

    // MARK: - Read / Write

    /// Stored preference, defaulting to `.system` for fresh installs and any
    /// legacy/unknown string left over from earlier builds.
    var current: Theme {
        get {
            guard let raw = defaults.string(forKey: themeKey),
                  let theme = Theme(rawValue: raw) else { return .system }
            return theme
        }
        set {
            defaults.set(newValue.rawValue, forKey: themeKey)
        }
    }

    /// Persist the theme and immediately push it onto every window of the
    /// active window scene. Callers shouldn't need to apply separately.
    func setTheme(_ theme: Theme) {
        current = theme
        applyToActiveWindowScene()
    }

    /// Re-apply the persisted theme. Called by SceneDelegate at launch so the
    /// window inherits the user's last choice before any VC is shown.
    func applyToActiveWindowScene() {
        let style = current.interfaceStyle
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = style
            }
        }
    }

    /// Apply the persisted theme to a specific window. Used by SceneDelegate
    /// when constructing a window before it's attached to the scene's `windows`
    /// collection — `applyToActiveWindowScene` would skip it in that gap.
    func apply(to window: UIWindow) {
        window.overrideUserInterfaceStyle = current.interfaceStyle
    }
}
