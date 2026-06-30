import XCTest
@testable import SnoozePay

/// Issue #425 — the brand `SPSwitch` in the Vibration / Critical Alerts /
/// Progressive rows was announced by VoiceOver as the generic "Переключатель"
/// with no context. Each switch now carries a contextual `accessibilityLabel`
/// taken from its row title. These tests find the switch in each cell's view
/// tree and assert the label, so a future refactor can't silently drop it.
final class SwitchAccessibilityLabelTests: XCTestCase {

    /// Depth-first search for the first `SPSwitch` in a view subtree — the
    /// switches are private subviews, so we locate them structurally rather
    /// than exposing internals just for the test.
    private func firstSwitch(in view: UIView) -> SPSwitch? {
        for subview in view.subviews {
            if let found = subview as? SPSwitch { return found }
            if let nested = firstSwitch(in: subview) { return nested }
        }
        return nil
    }

    func testVibrationCellSwitchHasContextualLabel() {
        let cell = VibrationCell(style: .default, reuseIdentifier: nil)
        cell.configure(isOn: true)
        let toggle = firstSwitch(in: cell.contentView)
        XCTAssertEqual(toggle?.accessibilityLabel, "Вибрация")
    }

    func testProgressiveScaleCellSwitchHasContextualLabel() {
        let cell = ProgressiveScaleCell(style: .default, reuseIdentifier: nil)
        cell.configure(isOn: false, chain: [50, 100], accessibilityChain: "50, 100")
        let toggle = firstSwitch(in: cell.contentView)
        XCTAssertEqual(toggle?.accessibilityLabel, "Прогрессивный режим")
    }

    func testSettingsIconRowSwitchTakesRowTitleAsLabel() {
        let cell = SettingsIconRowCell(style: .default, reuseIdentifier: nil)
        cell.configureSwitch(
            systemName: "bell.badge",
            iconColor: .systemRed,
            title: "Критические уведомления",
            isOn: false,
            onChange: { _ in }
        )
        let toggle = firstSwitch(in: cell.contentView)
        XCTAssertEqual(toggle?.accessibilityLabel, "Критические уведомления")
    }

    func testSettingsIconRowSwitchLabelClearedOnReuse() {
        let cell = SettingsIconRowCell(style: .default, reuseIdentifier: nil)
        cell.configureSwitch(
            systemName: "bell.badge",
            iconColor: .systemRed,
            title: "Критические уведомления",
            isOn: false,
            onChange: { _ in }
        )
        cell.prepareForReuse()
        let toggle = firstSwitch(in: cell.contentView)
        XCTAssertNil(toggle?.accessibilityLabel,
                     "Stale label must not leak to the next row the cell is reused for")
    }
}
