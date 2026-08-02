import XCTest
import UserNotifications
@testable import SnoozePay

final class PermissionsStatusConsistencyTests: XCTestCase {

    func testNotificationCardMatchesAlarmBackendInterpretation() {
        let statuses: [UNAuthorizationStatus] = [
            .authorized, .denied, .notDetermined, .provisional, .ephemeral
        ]

        for status in statuses {
            let cardStatus = PermissionsViewController.notificationPermissionStatus(for: status)
            let backendStatus = SystemAlarmBackendProbe.availability(forNotificationStatus: status)

            switch backendStatus {
            case .available:
                guard case .granted = cardStatus else {
                    return XCTFail("\(status) must look granted when it can ring an alarm")
                }
            case .unavailable, .notRequested:
                guard case .actionable = cardStatus else {
                    return XCTFail("\(status) must not look granted when it cannot ring an alarm")
                }
            case .unresolved, .indeterminate:
                XCTFail("A concrete notification status must resolve the backend")
            }
        }
    }
}
