import Foundation
import XCTest
@testable import SnoozePay

final class AppLoggerConcurrencyTests: XCTestCase {

    func testConcurrentEmittersDeliverEveryLineWithoutOverlappingCollectors() {
        let probe = DeliveryProbe()
        AppLogger.withTestSink({ _, _, message in
            probe.receive(message)
        }, perform: {
            DispatchQueue.concurrentPerform(iterations: 32) { index in
                AppLogger.emit(.audio, .error, String(index))
            }
        })

        XCTAssertEqual(probe.messages, Set((0..<32).map(String.init)))
        XCTAssertEqual(probe.maximumInFlight, 1, "ordinary sink collectors must never run concurrently")
        XCTAssertNil(AppLogger.testSink)
    }

    @MainActor
    func testDetachedEmitterIsObservedBeforeItsAsyncSinkRestores() async {
        let probe = DeliveryProbe()
        await AppLogger.withAsyncTestSink({ _, _, message in
            probe.receive(message)
        }, perform: {
            await Task.detached {
                AppLogger.emit(.audio, .error, "background line")
            }.value
        })

        XCTAssertEqual(probe.messages, ["background line"])
        XCTAssertNil(AppLogger.testSink)
    }

    func testSinkCanLogReentrantlyAndRestoreANestedThrowingScope() {
        struct ExpectedError: Error {}
        var messages: [String] = []
        AppLogger.withTestSink({ _, _, message in
            messages.append(message)
            guard message == "outer" else { return }
            AppLogger.emit(.audio, .error, "recursive")
            do {
                try AppLogger.withTestSink({ _, _, nested in
                    messages.append("nested: \(nested)")
                }, perform: {
                    AppLogger.emit(.audio, .error, "inner")
                    throw ExpectedError()
                })
                XCTFail("the nested body must throw")
            } catch is ExpectedError {
                // The outer sink must already be restored here.
            } catch {
                XCTFail("unexpected error: \(error)")
            }
            AppLogger.emit(.audio, .error, "restored")
        }, perform: {
            AppLogger.emit(.audio, .error, "outer")
        })

        XCTAssertEqual(messages, ["outer", "recursive", "nested: inner", "restored"])
        XCTAssertNil(AppLogger.testSink)
    }
}

private final class DeliveryProbe {
    private let lock = NSLock()
    private var inFlight = 0
    private(set) var maximumInFlight = 0
    private(set) var messages: Set<String> = []

    func receive(_ message: String) {
        lock.lock()
        inFlight += 1
        maximumInFlight = max(maximumInFlight, inFlight)
        messages.insert(message)
        lock.unlock()

        // Widen overlap between real concurrent callbacks without racing the
        // probe itself. This is workload, not a relaxed assertion deadline.
        Thread.sleep(forTimeInterval: 0.001)

        lock.lock()
        inFlight -= 1
        lock.unlock()
    }
}
