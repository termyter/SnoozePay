import XCTest
@testable import SnoozePay

/// Unit tests for ThemeService — persistence + theme/style mapping.
/// Window-application is exercised indirectly: we only assert the persisted
/// state and the enum -> UIUserInterfaceStyle mapping, since boot-strapping a
/// real UIWindowScene inside XCTest is brittle.
final class ThemeServiceTests: XCTestCase {

    private var testDefaults: UserDefaults!
    private var suiteName: String!
    private var service: ThemeService!

    override func setUp() {
        super.setUp()
        suiteName = "test.themeservice.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        service = ThemeService(defaults: testDefaults)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        service = nil
        testDefaults = nil
        super.tearDown()
    }

    // MARK: - Default state

    func testCurrent_freshInstall_isSystem() {
        XCTAssertEqual(service.current, .system)
    }

    func testCurrent_unknownStoredValue_fallsBackToSystem() {
        // Older / future / corrupted value should not crash; should default.
        testDefaults.set("solarized-dark", forKey: "preferred_theme")
        XCTAssertEqual(service.current, .system)
    }

    // MARK: - Persistence

    func testSetTheme_persistsDark() {
        service.setTheme(.dark)
        XCTAssertEqual(testDefaults.string(forKey: "preferred_theme"), "dark")
        XCTAssertEqual(service.current, .dark)
    }

    func testSetTheme_persistsLight() {
        service.setTheme(.light)
        XCTAssertEqual(testDefaults.string(forKey: "preferred_theme"), "light")
        XCTAssertEqual(service.current, .light)
    }

    func testSetTheme_persistsSystem() {
        service.setTheme(.dark) // first move away from default
        service.setTheme(.system)
        XCTAssertEqual(testDefaults.string(forKey: "preferred_theme"), "system")
        XCTAssertEqual(service.current, .system)
    }

    func testCurrent_setterAlsoPersists() {
        service.current = .light
        XCTAssertEqual(testDefaults.string(forKey: "preferred_theme"), "light")
    }

    // MARK: - Theme -> UIUserInterfaceStyle mapping

    func testInterfaceStyleMapping() {
        XCTAssertEqual(ThemeService.Theme.system.interfaceStyle, .unspecified)
        XCTAssertEqual(ThemeService.Theme.light.interfaceStyle, .light)
        XCTAssertEqual(ThemeService.Theme.dark.interfaceStyle, .dark)
    }

    // MARK: - apply(to:) — single-window path used by SceneDelegate

    func testApplyToWindow_appliesPersistedStyle_dark() {
        service.setTheme(.dark)
        let window = UIWindow()
        service.apply(to: window)
        XCTAssertEqual(window.overrideUserInterfaceStyle, .dark)
    }

    func testApplyToWindow_appliesPersistedStyle_light() {
        service.setTheme(.light)
        let window = UIWindow()
        service.apply(to: window)
        XCTAssertEqual(window.overrideUserInterfaceStyle, .light)
    }

    func testApplyToWindow_systemMapsToUnspecified() {
        service.setTheme(.system)
        let window = UIWindow()
        // Move it off the default, then re-apply, to verify the call actually
        // sets the style rather than relying on UIWindow's initial value.
        window.overrideUserInterfaceStyle = .dark
        service.apply(to: window)
        XCTAssertEqual(window.overrideUserInterfaceStyle, .unspecified)
    }
}
