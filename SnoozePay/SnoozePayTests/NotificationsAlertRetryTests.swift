import XCTest
import os
@testable import SnoozePay

private final class MidDismissalHost: UIViewController {
    override var isBeingDismissed: Bool { true }
}

private final class MidPresentationHost: UIViewController {
    override var isBeingPresented: Bool { true }
}

/// Records what it was asked to present and reports it back as presented,
/// calling no completion — so the read-back passes and no ALERT-SHOWN line
/// arrives later, outside this test.
private final class RecordingHost: UIViewController {
    private(set) var recorded: UIViewController?

    override var presentedViewController: UIViewController? { recorded }

    override func present(
        _ viewControllerToPresent: UIViewController,
        animated flag: Bool,
        completion: (() -> Void)? = nil
    ) {
        recorded = viewControllerToPresent
    }
}

/// The retry a transient refusal of the notifications-disabled alert earns
/// (#805). The timer is replaced by a seam that only collects the retry, so
/// each test runs it by hand: nothing here waits on the run loop.
@MainActor
final class NotificationsAlertRetryTests: XCTestCase {

    private var window: UIWindow!
    private var savedRetry: ((@escaping (UIViewController?) -> Void) -> Void)!
    private var pending: [(UIViewController?) -> Void] = []
    private var lines: [(level: OSLogType, message: String)] = []

    override func setUp() {
        super.setUp()
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        savedRetry = AppDelegate.scheduleNotificationsAlertRetry
        AppDelegate.scheduleNotificationsAlertRetry = { [unowned self] in self.pending.append($0) }
    }

    override func tearDown() {
        AppDelegate.scheduleNotificationsAlertRetry = savedRetry
        pending = []
        lines = []
        window.isHidden = true
        window = nil
        super.tearDown()
    }

    func testTransientRefusal_retriesOnTheRelocatedPresenter_insteadOfDropping() {
        let offscreen = UIViewController()
        offscreen.loadViewIfNeeded()
        let host = RecordingHost()
        attachToWindow(host)

        capture {
            AppDelegate.showNotificationsDisabledAlert(on: offscreen)
            XCTAssertEqual(pending.count, 1, "a refusal off the window hierarchy must schedule a retry")
            XCTAssertEqual(dropLines.count, 0, "the first refusal must not drop; the sink saw \(lines)")
            pending.first?(host)
        }

        XCTAssertTrue(
            host.recorded is UIAlertController,
            "the retry must present on the presenter it was handed, not on the original one"
        )
        XCTAssertEqual(dropLines.count, 0, "a retry that presented must not drop; the sink saw \(lines)")
        XCTAssertEqual(pending.count, 1, "a retry that presented must not schedule another")
        XCTAssertTrue(
            lines.contains { $0.level == .info && $0.message.contains("is not in the window hierarchy") },
            "the deferral must leave a line naming why; the sink saw \(lines)"
        )
    }

    func testRetryThatAlsoFails_dropsWithTheLine_andStops() {
        let offscreen = UIViewController()
        offscreen.loadViewIfNeeded()

        capture {
            AppDelegate.showNotificationsDisabledAlert(on: offscreen)
            pending.first?(nil)
        }

        XCTAssertEqual(pending.count, 1, "the retry is bounded: a failed retry must not schedule another")
        XCTAssertEqual(dropLines.count, 1, "a failed retry must end in one drop line; the sink saw \(lines)")
        XCTAssertEqual(dropLines.first?.level, .error)
        XCTAssertTrue(
            dropLines.first?.message.contains("UIViewController is not in the window hierarchy") == true,
            "the drop line must name why; it reads «\(dropLines.first?.message ?? "")»"
        )
    }

    /// No reason the guard names is permanent, so none of them may drop on the
    /// first refusal.
    func testEveryNamedRefusal_schedulesARetry() {
        let offscreen = UIViewController()
        offscreen.loadViewIfNeeded()
        let dismissing = MidDismissalHost()
        attachToWindow(dismissing)
        let presenting = MidPresentationHost()
        attachToWindow(presenting)

        for presenter in [offscreen, dismissing, presenting] {
            pending = []
            lines = []
            capture { AppDelegate.showNotificationsDisabledAlert(on: presenter) }
            XCTAssertEqual(pending.count, 1, "\(type(of: presenter)) must schedule a retry")
            XCTAssertEqual(dropLines.count, 0, "\(type(of: presenter)) must not drop at once; saw \(lines)")
        }
    }

    // MARK: - Helpers

    private var dropLines: [(level: OSLogType, message: String)] {
        lines.filter { $0.message.contains(AppDelegate.notificationsAlertDroppedErrorID) }
    }

    private func capture(_ body: () -> Void) {
        AppLogger.withTestSink({ [unowned self] _, level, text in
            self.lines.append((level: level, message: text))
        }, perform: body)
    }

    private func attachToWindow(_ host: UIViewController) {
        window.addSubview(host.view)
        XCTAssertNotNil(host.viewIfLoaded?.window, "test precondition: the presenter must be in the window")
    }
}
