import StoreKit
import UIKit
import XCTest
@testable import SnoozePay

@MainActor
final class StoreKitRestoreRequestTests: XCTestCase {
    private let russianBody = "Если есть незавершённая покупка, баланс обновится после её подтверждения. "
        + "Завершённые пополнения не восстанавливаются"
    private let englishBody = "If a purchase is still pending, your balance will update once it is confirmed. "
        + "Completed top-ups cannot be restored."

    func testRequestWaitsForSyncThenShowsNeutralResultAndCallsCompletionOnce() async throws {
        let controller = RestoreRequestController()
        let sync = SuspendedSync()
        var completions = 0
        let request = controller.performStoreKitRestore(
            onRequestCompleted: { completions += 1 }, sync: { try await sync.run() }
        )
        await sync.waitUntilStarted()
        XCTAssertTrue(controller.alerts.isEmpty, "A running sync is not a completed request or a credit")
        XCTAssertEqual(completions, 0)
        sync.complete()
        await request.value
        XCTAssertEqual(completions, 1)
        XCTAssertEqual(controller.alerts.count, 1, "A request with no pending purchase still has one neutral result")
        let alert = try XCTUnwrap(controller.alerts.first)
        XCTAssertEqual(alert.title, "Запрос отправлен")
        XCTAssertEqual(alert.message, russianBody)
        XCTAssertEqual(alert.actions.count, 1)
        XCTAssertEqual(alert.actions.first?.style, .default)
    }

    func testCancellationVariantsDoNotPresentResultOrCallCompletion() async {
        let cancellations: [Error] = [
            CancellationError(), StoreKitError.userCancelled,
            NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError),
            NSError(domain: SKErrorDomain, code: SKError.Code.paymentCancelled.rawValue)
        ]
        for cancellation in cancellations {
            let controller = RestoreRequestController()
            var completions = 0
            await controller.performStoreKitRestore(
                onRequestCompleted: { completions += 1 }, sync: { throw cancellation }
            ).value
            XCTAssertTrue(controller.alerts.isEmpty)
            XCTAssertEqual(completions, 0)
        }
    }

    func testUnrelatedDomainWithCancellationCodePresentsExistingErrorInsteadOfCancelling() async throws {
        let controller = RestoreRequestController()
        let error = NSError(domain: "StoreKitRestoreRequestTests.unrelated", code: NSUserCancelledError,
                            userInfo: [NSLocalizedDescriptionKey: "Unrelated failure"])
        var completions = 0
        await controller.performStoreKitRestore(
            onRequestCompleted: { completions += 1 }, sync: { throw error }
        ).value
        XCTAssertEqual(completions, 0)
        XCTAssertEqual(controller.alerts.count, 1)
        let alert = try XCTUnwrap(controller.alerts.first)
        XCTAssertEqual(alert.title, "Не удалось восстановить покупки")
        XCTAssertEqual(alert.message, "Unrelated failure\n\nЕсли проблема повторяется, свяжитесь с поддержкой.")
        XCTAssertEqual(alert.actions.count, 1)
    }

    func testSyncFailurePresentsExistingNetworkAdviceWithoutCallingCompletion() async throws {
        let controller = RestoreRequestController()
        var completions = 0
        await controller.performStoreKitRestore(
            onRequestCompleted: { completions += 1 }, sync: { throw URLError(.notConnectedToInternet) }
        ).value
        XCTAssertEqual(completions, 0)
        XCTAssertEqual(controller.alerts.count, 1)
        let alert = try XCTUnwrap(controller.alerts.first)
        XCTAssertEqual(alert.title, "Не удалось восстановить покупки")
        XCTAssertEqual(alert.message, "Проверьте подключение к интернету и попробуйте снова.")
    }

    func testCompiledRequestCopyPinsApprovedRussianAndEnglishWords() throws {
        for (language, title, body) in [("ru", "Запрос отправлен", russianBody),
                                        ("en", "Request Sent", englishBody)] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            XCTAssertEqual(bundle.localizedString(forKey: "deposit.restore.success.title",
                                                 value: nil, table: "Localizable"), title)
            XCTAssertEqual(bundle.localizedString(forKey: "deposit.restore.success.message",
                                                 value: nil, table: "Localizable"), body)
        }
    }
}

@MainActor
private final class RestoreRequestController: UIViewController {
    var alerts: [UIAlertController] = []

    override func present(
        _ viewControllerToPresent: UIViewController, animated: Bool, completion: (() -> Void)? = nil
    ) {
        if let alert = viewControllerToPresent as? UIAlertController { alerts.append(alert) }
        completion?()
    }
}

@MainActor
private final class SuspendedSync {
    private var started: CheckedContinuation<Void, Never>?
    private var completion: CheckedContinuation<Void, Error>?

    func run() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            completion = continuation
            started?.resume()
            started = nil
        }
    }

    func waitUntilStarted() async {
        guard completion == nil else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            started = continuation
        }
    }

    func complete() {
        let pending = completion
        completion = nil
        pending?.resume()
    }
}
