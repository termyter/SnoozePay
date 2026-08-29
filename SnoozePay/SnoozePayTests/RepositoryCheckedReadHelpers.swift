import XCTest
@testable import SnoozePay

/// Checked reads for tests (#271).
///
/// `fetchAll()` / `fetch(id:)` are `@available(*, deprecated)` because they
/// answer "the store could not be decoded" with the same value they use for
/// "the store is empty". Tests that merely want to read state back suffered
/// the same ambiguity as production did: a decode regression surfaced as
/// `XCTAssertEqual failed: 1 != 0` — an assertion pointing at the wrong thing.
///
/// These wrappers do the checked read and `XCTFail` on the error, so the test
/// that broke names the actual cause. They are non-throwing on purpose: the
/// migration then stays a one-token rename at ~75 call sites instead of also
/// threading `throws` through every test signature.
///
/// The handful of tests that pin the *lossy* contract itself keep calling the
/// deprecated fetchers directly and carry their own `@available(*, deprecated)`
/// annotation to stay warning-free.
extension AlarmRepository {

    func fetchAllOrFail(
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> [Alarm] {
        do {
            return try fetchAllChecked()
        } catch {
            XCTFail("fetchAllChecked() threw: \(error)", file: file, line: line)
            return []
        }
    }

    func fetchOrFail(
        id: UUID,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Alarm? {
        do {
            return try fetchChecked(id: id)
        } catch {
            XCTFail("fetchChecked(id:) threw: \(error)", file: file, line: line)
            return nil
        }
    }
}

extension TransactionRepository {

    func fetchAllOrFail(
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> [Transaction] {
        do {
            return try fetchAllChecked()
        } catch {
            XCTFail("fetchAllChecked() threw: \(error)", file: file, line: line)
            return []
        }
    }
}
