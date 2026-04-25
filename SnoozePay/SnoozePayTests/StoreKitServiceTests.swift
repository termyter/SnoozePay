import XCTest
@testable import SnoozePay

/// Smoke tests for StoreKitService.
///
/// NOTE: Fully exercising the `Transaction.updates` listener requires mocking
/// `StoreKit.Transaction.updates`, which is a built-in `AsyncStream` not
/// designed for substitution without a larger DI refactor. We therefore
/// limit coverage to:
///   - product ID → credit amount mapping (pure logic)
///   - shared instance reachability (smoke)
///
/// TODO(IOS-032+): Once StoreKit transaction handling is extracted behind a
/// protocol, add an end-to-end test that pushes a mock verified transaction
/// through `handle(transactionResult:)` and asserts the balance is credited
/// and the transaction is finished.
@MainActor
final class StoreKitServiceTests: XCTestCase {

    func testSharedInstance_isReachable() {
        // Touching `.shared` triggers `init`, which spawns the
        // `Transaction.updates` listener. If the listener crashed at start
        // this test would surface it.
        let service = StoreKitService.shared
        XCTAssertNotNil(service)
    }

    func testProductAmounts_coversAllProductIDs() {
        for productID in StoreKitService.productIDs {
            XCTAssertNotNil(
                StoreKitService.productAmounts[productID],
                "Missing credit amount mapping for \(productID)"
            )
        }
    }

    func testProductAmounts_matchProductIDSuffix() {
        // Each product ID encodes its RUB amount as the trailing component
        // (e.g. "...balance.149" → 149 RUB). Catch drift between the two tables.
        for (productID, amount) in StoreKitService.productAmounts {
            let suffix = productID.split(separator: ".").last.map(String.init) ?? ""
            XCTAssertEqual(
                Double(suffix),
                amount,
                "Product \(productID) maps to \(amount) but suffix says \(suffix)"
            )
        }
    }
}
