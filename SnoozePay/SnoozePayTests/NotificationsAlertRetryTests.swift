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

/// Returns from `present` having done nothing, as UIKit does when it declines
/// for a reason it does not publish.
private final class DecliningHost: UIViewController {
    override func present(
        _ viewControllerToPresent: UIViewController,
        animated flag: Bool,
        completion: (() -> Void)? = nil
    ) {}
}

/// Reports a fixed controller as presented, to build a chain without UIKit.
private final class ChainHost: UIViewController {
    var stubPresented: UIViewController?
    override var presentedViewController: UIViewController? { stubPresented }
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
        let drop = dropLines.first?.message ?? ""
        XCTAssertTrue(
            drop.contains("UIViewController is not in the window hierarchy after one retry"),
            "the drop line must name why, and that it came after the retry; it reads «\(drop)»"
        )
    }

    /// The drop names the retry's refusal, not the first one's.
    func testRetryRefusedForAnotherReason_dropsWithTheRetrysReason() {
        let offscreen = UIViewController()
        offscreen.loadViewIfNeeded()
        let dismissing = MidDismissalHost()
        attachToWindow(dismissing)

        capture {
            AppDelegate.showNotificationsDisabledAlert(on: offscreen)
            pending.first?(dismissing)
        }

        let drop = dropLines.first?.message ?? ""
        XCTAssertEqual(dropLines.count, 1, "the refused retry must drop with one line; the sink saw \(lines)")
        XCTAssertTrue(
            drop.contains("MidDismissalHost is being dismissed after one retry"),
            "the drop must name the retry's refusal; it reads «\(drop)»"
        )
        XCTAssertFalse(
            drop.contains("not in the window hierarchy"),
            "the first refusal's reason is stale by now; it reads «\(drop)»"
        )
    }

    /// The read-back's refusal has no known cause, so it drops at once.
    func testUnnamedRefusal_dropsWithoutARetry() {
        let host = DecliningHost()
        attachToWindow(host)

        capture { AppDelegate.showNotificationsDisabledAlert(on: host) }

        XCTAssertEqual(pending.count, 0, "a refusal only the read-back sees must not schedule a retry")
        XCTAssertEqual(dropLines.count, 1, "it must drop with one line; the sink saw \(lines)")
        XCTAssertFalse(
            dropLines.first?.message.contains("after one retry") ?? true,
            "no retry ran, so the line must not claim one; it reads «\(dropLines.first?.message ?? "")»"
        )
    }

    func testRetryDeclinedByTheReadBack_saysItCameAfterTheRetry() {
        let offscreen = UIViewController()
        offscreen.loadViewIfNeeded()
        let host = DecliningHost()
        attachToWindow(host)

        capture {
            AppDelegate.showNotificationsDisabledAlert(on: offscreen)
            pending.first?(host)
        }

        XCTAssertEqual(dropLines.count, 1, "the declined retry must drop with one line; the sink saw \(lines)")
        XCTAssertTrue(
            dropLines.first?.message.contains("DecliningHost did not put the alert up after one retry") == true,
            "it reads «\(dropLines.first?.message ?? "")»"
        )
    }

    func testRetryPresenter_isTheTopOfTheLocatedChain() {
        let leaf = UIViewController()
        let middle = ChainHost()
        middle.stubPresented = leaf
        let root = ChainHost()
        root.stubPresented = middle

        let found = capturing { AppDelegate.notificationsAlertRetryPresenter(from: .success(root)) }

        XCTAssertTrue(found === leaf, "the retry must get the topmost controller; got \(String(describing: found))")
        XCTAssertTrue(lines.isEmpty, "a found presenter needs no line; the sink saw \(lines)")
    }

    func testRetryPresenter_onALocatorMiss_logsTheMissAndFallsBack() {
        let found = capturing { AppDelegate.notificationsAlertRetryPresenter(from: .failure(.noScene)) }

        XCTAssertNil(found, "a miss must hand the retry nil, so it falls back to the original presenter")
        XCTAssertEqual(lines.count, 1, "the sink saw \(lines)")
        XCTAssertEqual(lines.first?.level, .info)
        XCTAssertTrue(
            lines.first?.message.contains(ActiveWindowLocator.Miss.noScene.rawValue) == true,
            "the line must carry the locator's reason; it reads «\(lines.first?.message ?? "")»"
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

        let presenters: [UIViewController] = [offscreen, dismissing, presenting]
        for presenter in presenters {
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
        capturing(body)
    }

    private func capturing<T>(_ body: () -> T) -> T {
        AppLogger.withTestSink({ [unowned self] _, level, text in
            self.lines.append((level: level, message: text))
        }, perform: body)
    }

    private func attachToWindow(_ host: UIViewController) {
        window.addSubview(host.view)
        XCTAssertNotNil(host.viewIfLoaded?.window, "test precondition: the presenter must be in the window")
    }
}
