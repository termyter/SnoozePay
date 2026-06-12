import StoreKit
import XCTest
@testable import SnoozePay

/// Unit tests for `StoreKitRestoreErrorCopy` — the error→Russian-copy mapping
/// extracted from the retired `TopUpViewController` into the reusable restore
/// helper used by `DepositBottomSheetViewController` (#281). Verifies each
/// error family maps to its actionable advice and unknown errors fall back to
/// the localized description plus support hint.
final class StoreKitRestoreErrorCopyTests: XCTestCase {

    private let networkAdvice = "Проверьте подключение к интернету и попробуйте снова."

    func testStoreKitNetworkError_mapsToNetworkAdvice() {
        XCTAssertEqual(StoreKitRestoreErrorCopy.message(for: StoreKitError.networkError(URLError(.timedOut))),
                       networkAdvice)
    }

    func testStoreKitNotEntitled_mapsToAppleIDAdvice() {
        XCTAssertEqual(StoreKitRestoreErrorCopy.message(for: StoreKitError.notEntitled),
                       "Войдите в Apple ID в Настройках и попробуйте снова.")
    }

    func testStoreKitNotAvailableInStorefront_mapsToRegionAdvice() {
        XCTAssertEqual(StoreKitRestoreErrorCopy.message(for: StoreKitError.notAvailableInStorefront),
                       "Покупки временно недоступны в вашем регионе.")
    }

    func testURLNotConnected_mapsToNetworkAdvice() {
        XCTAssertEqual(StoreKitRestoreErrorCopy.message(for: URLError(.notConnectedToInternet)),
                       networkAdvice)
    }

    func testNSURLDomainError_mapsToNetworkAdvice() {
        let nsError = NSError(domain: NSURLErrorDomain, code: -1009)
        XCTAssertEqual(StoreKitRestoreErrorCopy.message(for: nsError), networkAdvice)
    }

    func testUnknownError_fallsBackToDescriptionPlusSupportHint() {
        let nsError = NSError(domain: "com.snoozepay.test", code: 42,
                              userInfo: [NSLocalizedDescriptionKey: "Boom"])
        let message = StoreKitRestoreErrorCopy.message(for: nsError)
        XCTAssertTrue(message.contains("Boom"))
        XCTAssertTrue(message.contains("свяжитесь с поддержкой"))
    }
}
