import UIKit
import XCTest
@testable import SnoozePay

final class VolumePickerInteractionTests: XCTestCase {
    func testRoutedFadeChangesNotifyOncePreserveVolumeAndSurviveCreateAndEdit() throws {
        let suite = "test.volume.interaction.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = AlarmRepository(defaults: defaults, scheduler: NoopScheduler())
        var model = CreateAlarmViewModel(repository: repository, defaults: AlarmDefaults(defaults: defaults))
        model.enabled = false
        model.volume = 0.7
        var changes: [Bool] = []
        for expected in [true, false] {
            let picker = VolumePickerViewController(volume: model.volume, fadeIn: model.volumeFadeIn) { volume, fade in
                model.volume = volume
                model.volumeFadeIn = fade
                changes.append(fade)
            }
            picker.loadViewIfNeeded()
            picker.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            picker.view.layoutIfNeeded()
            let toggle: UISwitch = try control("volumePicker.fadeIn", in: picker.view)
            let point = toggle.convert(CGPoint(x: toggle.bounds.midX, y: toggle.bounds.midY), to: picker.view)
            let hit = picker.view.hitTest(point, with: nil)
            XCTAssertTrue(hit === toggle || hit?.isDescendant(of: toggle) == true)
            toggle.setOn(expected, animated: false)
            toggle.sendActions(for: .valueChanged)
            XCTAssertEqual(changes.count, expected ? 1 : 2, "one callback per accessory change")
            XCTAssertEqual(changes.last, expected)
            XCTAssertEqual(model.volume, 0.7)
            XCTAssertTrue(model.save())
            let stored = try XCTUnwrap(repository.fetchAllChecked().first)
            XCTAssertEqual(try repository.fetchAllChecked().count, 1, "editing updates the existing alarm")
            model = CreateAlarmViewModel(alarm: stored, repository: repository,
                                         defaults: AlarmDefaults(defaults: defaults))
            XCTAssertEqual(model.volumeFadeIn, expected)
            let reopened = VolumePickerViewController(volume: model.volume, fadeIn: model.volumeFadeIn)
            reopened.loadViewIfNeeded()
            let reopenedToggle: UISwitch = try control("volumePicker.fadeIn", in: reopened.view)
            XCTAssertEqual(reopenedToggle.isOn, expected)
        }
    }

    func testSliderStillQuantizesAndKeepsTheCurrentFadeChoice() throws {
        var changes: [(Float, Bool)] = []
        let picker = VolumePickerViewController(volume: 0.7, fadeIn: true) { changes.append(($0, $1)) }
        picker.loadViewIfNeeded()
        let slider: UISlider = try control("volumePicker.slider", in: picker.view)
        slider.value = 0.63
        slider.sendActions(for: .valueChanged)
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(try XCTUnwrap(changes.first?.0), 0.65, accuracy: 0.001)
        XCTAssertEqual(changes.first?.1, true)
    }

    private func control<T: UIControl>(_ identifier: String, in root: UIView) throws -> T {
        if let found = root as? T, found.accessibilityIdentifier == identifier { return found }
        for child in root.subviews {
            if let found: T = try? control(identifier, in: child) { return found }
        }
        throw NSError(domain: "VolumePickerInteractionTests.missingControl", code: 1)
    }

    private final class NoopScheduler: AlarmScheduling {
        func schedule(_ alarm: Alarm, completion: ((Result<Void, AlarmScheduler.SchedulingError>) -> Void)?) {
            completion?(.success(()))
        }
        func cancel(_ alarmID: UUID) {}
    }
}
