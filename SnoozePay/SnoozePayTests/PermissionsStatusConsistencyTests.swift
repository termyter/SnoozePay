import UIKit
import XCTest
@testable import SnoozePay

/// The permissions card and the alarms-list backend guard must never disagree
/// about "can this app ring an alarm".
///
/// They used to be checked against `UNAuthorizationStatus` — that axis is gone
/// with #472, because a notification is no longer a backend. Both now read the
/// same AlarmKit grant, and this test is what keeps the two mappings from
/// drifting: a green card over a gated list is the exact contradiction that made
/// #428 hard to diagnose.
final class PermissionsStatusConsistencyTests: XCTestCase {

    func testNotificationCardMatchesAlarmBackendInterpretation() {
        let states: [AlarmKitAuthorization] = [.authorized, .denied, .notDetermined, .unrecognized]

        for state in states {
            let cardStatus = PermissionsViewController.alarmPermissionStatus(for: state)
            let backendStatus = SystemAlarmBackendProbe.availability(forAlarmKitAuthorization: state)

            switch backendStatus {
            case .available:
                guard case .granted = cardStatus else {
                    return XCTFail("\(state) must look granted when it can ring an alarm")
                }
            case .unavailable, .notRequested, .indeterminate:
                guard case .actionable = cardStatus else {
                    return XCTFail("\(state) must not look granted when it cannot ring an alarm")
                }
            case .unresolved:
                XCTFail("A concrete authorization state must resolve the backend")
            }
        }
    }
}

extension PermissionsStatusConsistencyTests {
    func testBeforeRequestExplainsWhyAndRequestsOnlyAfterThePrimaryTap() {
        let probe = AlarmsListBackendGuardTests.StubProbe(result: .notRequested)
        probe.resultAfterAuthorizationRequest = .available
        let controller = permissionScreen(probe: probe)
        XCTAssertTrue(labels(in: controller.view).contains("Нужно разрешение на будильники"))
        let allow = button("permissions.allowButton", in: controller.view)
        XCTAssertEqual(allow?.accessibilityLabel, "Разрешить будильники")
        XCTAssertEqual(probe.authorizationRequestCount, 0)

        allow?.sendActions(for: .touchUpInside)

        XCTAssertEqual(probe.authorizationRequestCount, 1)
        XCTAssertNotNil(button("permissions.doneButton", in: controller.view))
        XCTAssertNil(button("permissions.notNowButton", in: controller.view))
    }

    func testNotNowLeavesTheGrantUnchangedAndPermitsBrowsing() {
        let key = PermissionsViewController.hasBeenShownKey
        let saved = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }
        for state in [AlarmBackendAvailability.notRequested, .unavailable] {
            let probe = AlarmsListBackendGuardTests.StubProbe(result: state)
            let controller = permissionScreen(probe: probe)
            var finished = 0
            controller.onFinished = { finished += 1 }
            button("permissions.notNowButton", in: controller.view)?.sendActions(for: .touchUpInside)
            XCTAssertEqual(finished, 1)
            XCTAssertEqual(probe.result, state)
            XCTAssertEqual(probe.authorizationRequestCount, 0)
            XCTAssertNil(button("permissions.doneButton", in: controller.view))
        }
    }

    func testReturningFromSettingsRefreshesTheScreenWithoutRelaunch() {
        let center = NotificationCenter()
        let probe = AlarmsListBackendGuardTests.StubProbe(result: .unavailable)
        let monitor = AlarmBackendMonitor(probe: probe, notificationCenter: center)
        let controller = PermissionsViewController(backendMonitor: monitor)
        controller.loadViewIfNeeded()
        XCTAssertTrue(labels(in: controller.view).contains("Доступ к будильникам выключен"))
        XCTAssertTrue(labels(in: controller.view).contains("НАСТРОЙКИ"))
        XCTAssertEqual(button("permissions.allowButton", in: controller.view)?.accessibilityLabel, "Открыть настройки")

        probe.result = .available
        center.post(name: AlarmBackendMonitor.foregroundNotificationName, object: nil)

        XCTAssertNotNil(button("permissions.doneButton", in: controller.view))
        XCTAssertNil(button("permissions.notNowButton", in: controller.view))
        XCTAssertEqual(probe.authorizationRequestCount, 0)
    }

    private func permissionScreen(probe: AlarmsListBackendGuardTests.StubProbe) -> PermissionsViewController {
        let monitor = AlarmBackendMonitor(probe: probe, notificationCenter: NotificationCenter())
        let controller = PermissionsViewController(backendMonitor: monitor)
        controller.loadViewIfNeeded()
        return controller
    }

    private func button(_ identifier: String, in view: UIView) -> SPButton? {
        if let button = view as? SPButton, button.accessibilityIdentifier == identifier { return button }
        return view.subviews.compactMap { button(identifier, in: $0) }.first
    }

    private func labels(in view: UIView) -> [String] {
        ((view as? UILabel)?.text.map { [$0] } ?? []) + view.subviews.flatMap { labels(in: $0) }
    }
}
