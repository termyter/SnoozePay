import UIKit
import XCTest
import os
@testable import SnoozePay

/// #1201: the sheet's own Ask to Buy / SCA purchase is approved, then crediting
/// fails (`.notRecorded`, `.refusedCurrency`) while the pending notice is still
/// up. UIKit takes one alert at a time: the deposit sheet only logged the
/// failure, and the firing sheet's acknowledgement guard dropped it. The user
/// kept reading «the balance will be topped up», which may now be false.
///
/// The failure now joins the notice in place, or, once OK was tapped, follows
/// it. Mounted for real, as in `TopUpSuccessDismissalTests`: a host presents
/// the sheet and the sheet presents its notice.
@MainActor
final class TopUpFailureBehindOwnAlertTests: XCTestCase {
    private var window: UIWindow?
    private let pending = StoreKitService.purchasePendingMessage
    private let failure = StoreKitService.ledgerLockedFailureMessage
    private let secondFailure = StoreKitService.foreignCurrencyFailureMessage
    private let thirdFailure = StoreKitService.degradedDedupFailureMessage

    /// On screen at once, in the alert the user is reading, under the failure
    /// title. The notice's paragraph stays above it: the failure carries no
    /// transaction identity and may be another purchase's. OK closes it and
    /// nothing follows, so it is shown once.
    func testFailureBehindEitherSheetsNoticeIsShownInItAndNotAgainAfterOK() throws {
        for firing in [false, true] {
            let mounted = try mountBehindNotice(firing: firing)
            let lines = uiLines { mounted.postFailure(failure) }
            XCTAssertEqual(lines, ["default: \(mounted.logName): alert added to its own alert"])
            XCTAssertTrue(mounted.sheet.presentedViewController === mounted.notice, mounted.diagnostics)
            XCTAssertEqual(mounted.notice.title, mounted.failureTitle)
            XCTAssertEqual(mounted.notice.message, paragraphs(pending, failure))

            answer(mounted.notice, on: mounted)
            drainMainQueue()
            XCTAssertNil(mounted.sheet.presentedViewController, "Shown once: " + mounted.diagnostics)
            XCTAssertTrue(try mounted.purchaseButton().isEnabled, mounted.logName)
        }
    }

    /// Two failures behind one notice are both read; the same failure delivered
    /// twice (the purchase, then `Transaction.updates`) is read once.
    func testTwoFailuresBehindEitherSheetsNoticeAreEachShownOnce() throws {
        for firing in [false, true] {
            let mounted = try mountBehindNotice(firing: firing)
            mounted.postFailure(failure)
            mounted.postFailure(secondFailure)
            mounted.postFailure(failure)
            XCTAssertTrue(mounted.sheet.presentedViewController === mounted.notice, mounted.diagnostics)
            XCTAssertEqual(mounted.notice.title, mounted.failureTitle)
            XCTAssertEqual(mounted.notice.message, paragraphs(pending, failure, secondFailure))

            answer(mounted.notice, on: mounted)
            drainMainQueue()
            XCTAssertNil(mounted.sheet.presentedViewController, "One alert for both: " + mounted.diagnostics)
        }
    }

    /// OK was tapped and the notice is on its way out when failures land. UIKit
    /// takes no alert until it has gone and nothing joins an alert that is
    /// going, so they follow it as one alert. A repeat of what the notice said
    /// is not shown again.
    func testFailuresArrivingAsEitherSheetsNoticeGoesAreShownOnceItHasGone() throws {
        for firing in [false, true] {
            let mounted = try mountBehindNotice(firing: firing)
            mounted.postFailure(failure)
            mounted.notice.dismiss(animated: true)
            XCTAssertTrue(mounted.notice.isBeingDismissed, "The user's OK is under way")
            let lines = uiLines {
                mounted.postFailure(failure)
                mounted.postFailure(secondFailure)
                mounted.postFailure(thirdFailure)
            }
            XCTAssertEqual(lines, Array(repeating: "default: \(mounted.deferredLine)", count: 2))
            XCTAssertEqual(mounted.notice.message, paragraphs(pending, failure), "Nothing joins a going alert")
            XCTAssertTrue(spin { mounted.notice.presentingViewController == nil }, mounted.diagnostics)
            // The firing sheet's OK acknowledges once the alert has gone (#950).
            mounted.firing?.acknowledgePurchaseFailure()

            let expected = paragraphs(secondFailure, thirdFailure)
            XCTAssertTrue(spin { mounted.presentedAlert?.message == expected }, mounted.diagnostics)
            let next = try XCTUnwrap(mounted.presentedAlert)
            XCTAssertFalse(next === mounted.notice)
            XCTAssertEqual(next.title, mounted.failureTitle)
            XCTAssertTrue(spin { !next.isBeingPresented }, mounted.diagnostics)
            answer(next, on: mounted)
            drainMainQueue()
            XCTAssertNil(mounted.sheet.presentedViewController, "Shown once: " + mounted.diagnostics)
            XCTAssertTrue(try mounted.purchaseButton().isEnabled, mounted.logName)
        }
    }

    /// The sheet goes while its notice carries a failure: the failure went with
    /// the alert it was shown in, nothing turns up later on the sheet or its
    /// presenter, and the firing sheet's pause ends once.
    func testFailureBehindEitherSheetsNoticeGoesWithTheSheet() throws {
        for firing in [false, true] {
            let mounted = try mountBehindNotice(firing: firing)
            mounted.postFailure(failure)
            XCTAssertEqual(mounted.notice.message, paragraphs(pending, failure))

            mounted.host.dismiss(animated: false)
            XCTAssertTrue(spin { mounted.host.presentedViewController == nil }, mounted.diagnostics)
            mounted.firing?.acknowledgePurchaseFailure()
            drainMainQueue()
            XCTAssertNil(mounted.host.presentedViewController, mounted.diagnostics)
            XCTAssertNil(mounted.sheet.presentedViewController, mounted.diagnostics)
            XCTAssertEqual(mounted.notice.message, paragraphs(pending, failure))
            XCTAssertEqual(mounted.calls.lifecycle, firing ? [true, false] : [])
        }
    }

    /// The firing sheet's deferred failure waits for the notice's OK. If the
    /// sheet closes first, the pause has ended and nothing can show it: an
    /// error line says so, and no alert turns up.
    func testFiringSheetsDeferredFailureIsReportedWhenThePauseEndsBeforeItsOK() throws {
        let mounted = try mountBehindNotice(firing: true)
        mounted.notice.dismiss(animated: true)
        XCTAssertTrue(mounted.notice.isBeingDismissed, "The user's OK is under way")
        mounted.postFailure(failure)
        XCTAssertTrue(spin { mounted.notice.presentingViewController == nil }, mounted.diagnostics)

        let lines = uiLines {
            mounted.host.dismiss(animated: false)
            _ = spin { mounted.host.presentedViewController == nil }
        }
        XCTAssertEqual(lines, ["error: FiringTopUpSheet: deferred alert not shown, the pause ended before its OK"])
        mounted.firing?.acknowledgePurchaseFailure()
        drainMainQueue()
        XCTAssertNil(mounted.host.presentedViewController, mounted.diagnostics)
        XCTAssertNil(mounted.sheet.presentedViewController, mounted.diagnostics)
        XCTAssertEqual(mounted.calls.lifecycle, [true, false])
    }

    /// A screen over the deposit sheet's notice, as an alarm's firing screen and
    /// its top-up sheet are in #1190, is the routing case: that screen's own
    /// failure reaches this ungated observer too, and has been shown there.
    /// Joined into the covered notice it would be read twice, so the notice is
    /// left alone and the refusal logged, as before #1201.
    func testFailureReachingTheDepositSheetsCoveredNoticeLeavesTheNoticeAlone() throws {
        let mounted = try mountBehindNotice(firing: false)
        let cover = UIViewController()
        cover.modalPresentationStyle = .fullScreen
        var presented = false
        mounted.notice.present(cover, animated: false) { presented = true }
        XCTAssertTrue(spin { presented }, mounted.diagnostics)

        let lines = uiLines { mounted.postFailure(failure) }
        XCTAssertEqual(lines, ["error: DepositSheet: alert not shown, UIAlertController is presented"])
        XCTAssertNil(mounted.notice.title)
        XCTAssertEqual(mounted.notice.message, pending)
        XCTAssertTrue(cover.presentingViewController === mounted.notice, mounted.diagnostics)
    }

    // MARK: - Helpers

    /// What a test records from the sheet's seams.
    private final class Calls {
        var lifecycle: [Bool] = []
    }

    /// One sheet, mounted in a key window, its purchase tapped and its pending notice up.
    @MainActor
    private struct Mounted {
        let sheet: UIViewController
        let host: UIViewController
        let notice: UIAlertController
        let center: NotificationCenter
        let calls: Calls

        var firing: FiringTopUpBottomSheetViewController? { sheet as? FiringTopUpBottomSheetViewController }
        var logName: String { firing == nil ? "DepositSheet" : "FiringTopUpSheet" }
        var deferredLine: String {
            firing == nil ? "DepositSheet: alert deferred, its own alert is being dismissed"
                : "FiringTopUpSheet: alert deferred until its own alert's OK"
        }
        var failureTitle: String {
            Localized.text(firing == nil ? "common.purchase_failed.title" : "firing.alert.purchase_failed.title")
        }
        var presentedAlert: UIAlertController? { sheet.presentedViewController as? UIAlertController }
        var diagnostics: String { "\(logName): " + presentationDiagnostics(rootedAt: host) }

        func postFailure(_ message: String) {
            center.post(name: StoreKitService.purchaseFailedNotification, object: nil,
                        userInfo: [StoreKitService.messageUserInfoKey: message])
        }

        func purchaseButton() throws -> SPButton { try topUpPurchaseButton(in: sheet) }
    }

    /// The deposit sheet registers its #45 subscription with a store of its own,
    /// so nothing here touches `StoreKitService.shared`.
    private func mountBehindNotice(firing: Bool) throws -> Mounted {
        unmount()
        // The backlog earlier suites left on the main queue is spent here, not
        // inside the first wait below (#618).
        drainMainQueue()
        let center = NotificationCenter()
        let defaults = makeIsolatedDefaults()
        let balance = BalanceService(defaults: defaults, notificationCenter: center)
        let store = StoreKitService(notificationPoster: LocalNotificationPosterSpy(), defaults: defaults)
        let calls = Calls()
        let offer: (String) -> TopUpOffer? = {
            TopUpOffer(productID: $0, price: 149, currencyCode: "RUB", displayPrice: "149 ₽")
        }
        let sheet: UIViewController = firing
            ? FiringTopUpBottomSheetViewController(
                balance: balance, notificationCenter: center, scheduleSuccessDismissal: { _, _ in },
                purchaseProduct: { _ in }, pauseLifecycle: { calls.lifecycle.append($0) }, offerProvider: offer)
            : DepositBottomSheetViewController(
                balance: balance, notificationCenter: center, scheduleSuccessDismissal: { _, _ in },
                purchaseProduct: { _ in }, offerProvider: offer, feedbackStore: store)
        addTeardownBlock { [weak self] in
            self?.unmount()
            XCTAssertFalse(store.hasPurchaseFeedbackSubscriber, "The sheet ends the #45 subscription it began")
        }

        let host = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.windowScene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        window.rootViewController = host
        window.makeKeyAndVisible()
        self.window = window
        var presented = false
        host.present(sheet, animated: false) { presented = true }
        XCTAssertTrue(spin { presented }, "\(type(of: sheet)) must be up before the test drives it")

        try topUpPurchaseButton(in: sheet).sendActions(for: .touchUpInside)
        center.post(name: StoreKitService.purchasePendingNotification, object: nil)
        let notice = try XCTUnwrap(sheet.presentedViewController as? UIAlertController,
                                   presentationDiagnostics(rootedAt: host))
        XCTAssertEqual(notice.view.accessibilityIdentifier, "purchase.pendingNotice")
        XCTAssertNil(notice.title)
        XCTAssertEqual(notice.message, pending)
        XCTAssertTrue(spin { !notice.isBeingPresented && notice.viewIfLoaded?.window != nil },
                      "The notice must finish presenting: " + presentationDiagnostics(rootedAt: host))
        return Mounted(sheet: sheet, host: host, notice: notice, center: center, calls: calls)
    }

    /// The user's OK: the alert goes, then the firing sheet acknowledges, as its
    /// OK action does once the dismissal has completed.
    private func answer(_ alert: UIAlertController, on mounted: Mounted) {
        alert.dismiss(animated: false)
        XCTAssertTrue(spin { alert.presentingViewController == nil }, mounted.diagnostics)
        mounted.firing?.acknowledgePurchaseFailure()
    }

    /// Closes whatever a failed run left up, so the sheet's appearance is balanced.
    private func unmount() {
        if let host = window?.rootViewController, host.presentedViewController != nil {
            host.dismiss(animated: false)
            _ = spin { host.presentedViewController == nil }
        }
        window?.isHidden = true
        window = nil
    }

    private func paragraphs(_ texts: String...) -> String {
        texts.joined(separator: "\n\n")
    }

    /// Turns the main run loop until `condition` holds, for at most `timeout`.
    private func spin(timeout: TimeInterval = 10, until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return condition()
    }

    /// The `.ui` lines `emit` wrote during `action`, each prefixed by its level.
    private func uiLines(during action: () -> Void) -> [String] {
        var lines: [String] = []
        AppLogger.withTestSink({ category, level, message in
            guard category == .ui else { return }
            let prefix = level == .error ? "error" : level == .default ? "default" : "level \(level.rawValue)"
            lines.append("\(prefix): \(message)")
        }, perform: action)
        return lines
    }
}

/// Either sheet's purchase button, found by its accessibility identifier.
@MainActor
private func topUpPurchaseButton(in sheet: UIViewController) throws -> SPButton {
    let id = sheet is FiringTopUpBottomSheetViewController ? "firingTopUp.purchaseButton" : "deposit.purchaseButton"
    func descendants(_ view: UIView) -> [UIView] { view.subviews.flatMap { [$0] + descendants($0) } }
    return try XCTUnwrap(descendants(sheet.view).compactMap { $0 as? SPButton }.first {
        $0.accessibilityIdentifier == id
    })
}
