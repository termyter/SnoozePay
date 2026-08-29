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
