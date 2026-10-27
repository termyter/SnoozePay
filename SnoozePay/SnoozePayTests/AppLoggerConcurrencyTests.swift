import Foundation
import os
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
                XCTAssertFalse(Thread.isMainThread)
                AppLogger.emit(.audio, .error, "background line")
            }.value
        })

        XCTAssertEqual(probe.messages, ["background line"])
        XCTAssertNil(AppLogger.testSink)
    }

    func testSerialSinkScopesCanChangeWhileBackgroundEmittersAreRunning() {
        let finished = expectation(description: "background logging finished")
        let probe = DeliveryProbe()
        DispatchQueue.global().async {
            for index in 0..<128 {
                AppLogger.emit(.audio, .error, "background \(index)")
            }
            finished.fulfill()
        }

        for index in 0..<32 {
            AppLogger.withTestSink({ _, _, message in
                probe.receive(message)
            }, perform: {
                AppLogger.emit(.audio, .error, "scoped \(index)")
            })
        }
        wait(for: [finished], timeout: 5)

        let scoped = probe.messages.filter { $0.hasPrefix("scoped ") }
        XCTAssertEqual(Set(scoped), Set((0..<32).map { "scoped \($0)" }))
        XCTAssertEqual(probe.maximumInFlight, 1)
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

nonisolated private final class DeliveryProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var inFlight = 0
    private var peak = 0
    private var received: Set<String> = []

    var maximumInFlight: Int {
        lock.lock()
        defer { lock.unlock() }
        return peak
    }

    var messages: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return received
    }

    func receive(_ message: String) {
        lock.lock()
        inFlight += 1
        peak = max(peak, inFlight)
        received.insert(message)
        lock.unlock()

        // Widen overlap between real concurrent callbacks without racing the
        // probe itself. This is workload, not a relaxed assertion deadline.
        Thread.sleep(forTimeInterval: 0.001)

        lock.lock()
        inFlight -= 1
        lock.unlock()
    }
}
