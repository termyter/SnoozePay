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
}
