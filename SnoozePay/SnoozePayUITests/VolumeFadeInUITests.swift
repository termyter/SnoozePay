import XCTest

/// Real taps cover the disabled-ancestor regression that sendActions bypasses.
final class VolumeFadeInUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        XCUIApplication().terminate()
        super.tearDown()
    }

    func testFadeInTogglesOffAndOnInLightAppearance() {
        verifyNativeControls(appearance: "light")
    }

    func testFadeInTogglesOffAndOnInDarkAppearance() {
        verifyNativeControls(appearance: "dark")
    }

    private func verifyNativeControls(appearance: String) {
        let app = XCUIApplication()
        app.launchArguments = ["-uitour", "volume-picker", "-uitour-appearance", appearance,
                               "-uitour-alarmkit", "granted"]
        app.launch()
        let toggle = app.switches["volumePicker.fadeIn"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 15))
        XCTAssertTrue(toggle.isHittable)
        assertSwitch(toggle, isOn: true)
        // Each state change must follow ONE native tap: retrying a toggle
        // could mask a dropped tap or undo a successfully delivered one.
        toggle.tap()
        assertSwitch(toggle, isOn: false)
        toggle.tap()
        assertSwitch(toggle, isOn: true)

        let percentage = app.staticTexts["volumePicker.percentage"]
        XCTAssertEqual(percentage.label, "70%")
        let slider = app.sliders["volumePicker.slider"]
        XCTAssertTrue(slider.isHittable)
        slider.adjust(toNormalizedSliderPosition: 0.2)
        let moved = NSPredicate(format: "label != %@", "70%")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: moved, object: percentage)],
                                     timeout: 5), .completed)
        assertSwitch(toggle, isOn: true)
    }

    private func assertSwitch(_ toggle: XCUIElement, isOn: Bool,
                              file: StaticString = #filePath, line: UInt = #line) {
        let state = NSPredicate(format: "value == %@", isOn ? "1" : "0")
        let changed = XCTNSPredicateExpectation(predicate: state, object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed,
                       "the native fade-in switch must be \(isOn ? "ON" : "OFF")", file: file, line: line)
    }
}
