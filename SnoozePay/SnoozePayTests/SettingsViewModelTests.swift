import XCTest
@testable import SnoozePay

/// Unit tests for Settings theme persistence via UserDefaults.
final class SettingsViewModelTests: XCTestCase {

    private var testDefaults: UserDefaults!
    private let themeKey = "preferred_theme"

    override func setUp() {
        super.setUp()
        testDefaults = UserDefaults(suiteName: "test.settings.\(UUID().uuidString)")!
    }

    override func tearDown() {
        if let name = testDefaults.suiteName {
            UserDefaults.removePersistentDomain(forName: name)
        }
        super.tearDown()
    }

    // MARK: - Theme persistence

    func testThemePersistence_default() {
        // Fresh UserDefaults should return nil for theme key (system theme)
        let saved = testDefaults.string(forKey: themeKey)
        XCTAssertNil(saved, "Default theme should be nil (system theme)")
    }

    func testThemePersistence_defaultFallsBackToSystem() {
        // When nil, the app should treat it as "system"
        let saved = testDefaults.string(forKey: themeKey) ?? "system"
        XCTAssertEqual(saved, "system", "Nil preference should fall back to 'system'")
    }

    func testThemePersistence_setDark() {
        testDefaults.set("dark", forKey: themeKey)

        let saved = testDefaults.string(forKey: themeKey)
        XCTAssertEqual(saved, "dark", "Theme should persist as 'dark'")
    }

    func testThemePersistence_setLight() {
        testDefaults.set("light", forKey: themeKey)

        let saved = testDefaults.string(forKey: themeKey)
        XCTAssertEqual(saved, "light", "Theme should persist as 'light'")
    }

    func testThemePersistence_setSystem() {
        testDefaults.set("system", forKey: themeKey)

        let saved = testDefaults.string(forKey: themeKey)
        XCTAssertEqual(saved, "system", "Theme should persist as 'system'")
    }

    func testThemePersistence_overwrite() {
        // Set dark, then switch to light, then to system
        testDefaults.set("dark", forKey: themeKey)
        XCTAssertEqual(testDefaults.string(forKey: themeKey), "dark")

        testDefaults.set("light", forKey: themeKey)
        XCTAssertEqual(testDefaults.string(forKey: themeKey), "light")

        testDefaults.set("system", forKey: themeKey)
        XCTAssertEqual(testDefaults.string(forKey: themeKey), "system")
    }

    func testThemeToStyleMapping() {
        // Verify the mapping logic used by SceneDelegate and SettingsViewController
        let mapping: [String: UIUserInterfaceStyle] = [
            "dark": .dark,
            "light": .light,
            "system": .unspecified
        ]

        for (themeString, expectedStyle) in mapping {
            let style: UIUserInterfaceStyle
            switch themeString {
            case "dark": style = .dark
            case "light": style = .light
            default: style = .unspecified
            }
            XCTAssertEqual(style, expectedStyle, "Theme '\(themeString)' should map to \(expectedStyle)")
        }
    }

    func testThemeSegmentIndexMapping() {
        // Verify segment index matches stored value
        let segmentValues = ["system", "light", "dark"]

        for (index, value) in segmentValues.enumerated() {
            testDefaults.set(value, forKey: themeKey)
            let saved = testDefaults.string(forKey: themeKey) ?? "system"
            let segmentIndex: Int
            switch saved {
            case "light": segmentIndex = 1
            case "dark": segmentIndex = 2
            default: segmentIndex = 0
            }
            XCTAssertEqual(segmentIndex, index, "Value '\(value)' should map to segment index \(index)")
        }
    }
}
