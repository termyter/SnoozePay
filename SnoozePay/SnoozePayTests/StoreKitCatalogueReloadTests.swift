import XCTest
import UIKit
@testable import SnoozePay

/// A catalogue loader the test completes by hand: queued results return at
/// once, otherwise a call suspends until `complete(with:)`.
@MainActor
private final class CatalogueLoaderStub {
    private(set) var calls = 0
    var immediate: [Result<LoadedCatalogue, Error>] = []
    var onCall: (() -> Void)?
    private var suspended: [CheckedContinuation<LoadedCatalogue, Error>] = []

    func load() async throws -> LoadedCatalogue {
        calls += 1
        onCall?()
        if !immediate.isEmpty { return try immediate.removeFirst().get() }
        return try await withCheckedThrowingContinuation { suspended.append($0) }
    }

    func complete(with result: Result<LoadedCatalogue, Error>, line: UInt = #line) {
        guard !suspended.isEmpty else {
            XCTFail("no catalogue load is in flight to complete", line: line)
            return
        }
        suspended.removeFirst().resume(with: result)
    }
}

private struct OfflineError: Error {}

/// #1109 step 5c: the catalogue reloads on a storefront change and on a
/// foreground after an unhealthy load. Every seam is injected — no real
/// StoreKit, no `.shared`, no `.standard`, no `NotificationCenter.default`.
@MainActor
final class StoreKitCatalogueReloadTests: XCTestCase {

    private var center: NotificationCenter!
    private var scaleStore: SnoozePriceScaleStore!
    private var loader: CatalogueLoaderStub!
    private var storefront: AsyncStream<Void>.Continuation!
    private var service: StoreKitService!
    private var posterSpy: LocalNotificationPosterSpy!

    private let usd = Currency(code: "USD")!
    private let eur = Currency(code: "EUR")!
    private let usdScale = SnoozePriceScale(
        currency: Currency(code: "USD")!, tiers: ["0.99", "1.99", "2.99"].map { Decimal(string: $0)! }
    )!

    override func setUp() {
        super.setUp()
        center = NotificationCenter()
        let defaults = makeIsolatedDefaults()
        scaleStore = SnoozePriceScaleStore(defaults: defaults, notificationCenter: center)
        loader = CatalogueLoaderStub()
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        storefront = continuation
        let loader = loader!
        posterSpy = LocalNotificationPosterSpy()
        service = StoreKitService(
            notificationPoster: posterSpy, defaults: defaults, priceScaleStore: scaleStore,
            catalogueLoader: { try await loader.load() }, storefrontChanges: stream, foregroundCenter: center
        )
    }

    override func tearDown() {
        service = nil
        storefront.finish()
        super.tearDown()
    }

    // MARK: - Helpers

    private func catalogue(_ prices: [String], code: String = "USD") -> LoadedCatalogue {
        LoadedCatalogue(offers: zip(StoreKitService.productIDs, prices).map { id, price in
            TopUpOffer(productID: id, price: Decimal(string: price)!, currencyCode: code,
                       displayPrice: "\(price) \(code)")!
        })
    }

    private var fullUSD: LoadedCatalogue { catalogue(["0.99", "1.99", "2.99", "4.99", "9.99"]) }
    private var partialUSD: LoadedCatalogue { catalogue(["1.99", "2.99", "4.99", "9.99"]) }

    private func expectLoaderCall(_ description: String) -> XCTestExpectation {
        let call = expectation(description: description)
        loader.onCall = { call.fulfill() }
        return call
    }

    private func expectNoLoaderCall(_ description: String) -> XCTestExpectation {
        let call = expectation(description: description)
        call.isInverted = true
        loader.onCall = { call.fulfill() }
        return call
    }

    private func scaleChanged() -> XCTestExpectation {
        XCTNSNotificationExpectation(
            name: SnoozePriceScaleStore.snoozePriceScaleChangedNotification, object: scaleStore,
            notificationCenter: center
        )
    }

    /// Fulfilled when the current reload run, follow-up included, has finished.
    private func expectSettled(_ description: String) -> XCTestExpectation {
        let settled = expectation(description: description)
        service.onCatalogueReloadsSettled = { settled.fulfill() }
        return settled
    }

    private func expectNoScaleChange(_ description: String) -> (XCTestExpectation, NSObjectProtocol) {
        let posts = expectation(description: description)
        posts.isInverted = true
        let token = center.addObserver(
            forName: SnoozePriceScaleStore.snoozePriceScaleChangedNotification, object: nil, queue: nil
        ) { _ in posts.fulfill() }
        return (posts, token)
    }

    private func postForeground() {
        center.post(name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    /// Seeds the catalogue state through the one load path, outside the trigger machinery.
    private func seed(_ result: Result<LoadedCatalogue, Error>) async {
        loader.immediate = [result]
        await service.loadProducts(.storefrontChanged)
        loader.onCall = nil
    }

    // MARK: - Storefront updates

    func testStorefrontUpdateReloadsAndRecordsTheScaleOnTheInjectedCenter() async {
        let call = expectLoaderCall("storefront update reaches the loader")
        storefront.yield()
        await fulfillment(of: [call], timeout: 2)
        XCTAssertNil(scaleStore.scale(for: usd))

        let recorded = scaleChanged()
        loader.complete(with: .success(fullUSD))
        await fulfillment(of: [recorded], timeout: 2)
        XCTAssertEqual(scaleStore.scale(for: usd), usdScale)
        XCTAssertEqual(scaleStore.lastStorefrontCurrency, usd)
        XCTAssertEqual(service.catalogue.offers.map(\.productID), StoreKitService.productIDs)
        XCTAssertFalse(service.needsCatalogueReload)
    }

    func testStorefrontSwitchRecordsTheNewCurrencyAndKeepsTheOldScale() async {
        await seed(.success(fullUSD))
        let call = expectLoaderCall("storefront switch reloads")
        storefront.yield()
        await fulfillment(of: [call], timeout: 2)

        let recorded = scaleChanged()
        loader.complete(with: .success(catalogue(["0.99", "1.99", "2.99", "4.99", "9.99"], code: "EUR")))
        await fulfillment(of: [recorded], timeout: 2)
        XCTAssertEqual(scaleStore.scale(for: eur)?.currency, eur)
        XCTAssertEqual(scaleStore.lastStorefrontCurrency, eur)
        XCTAssertEqual(scaleStore.scale(for: usd), usdScale, "the old wallet currency keeps its scale")
    }

    func testPartialReloadReplacesProductsButKeepsTheStoredScale() async {
        await seed(.success(fullUSD))
        let (noPost, token) = expectNoScaleChange("a partial reload records nothing")
        defer { center.removeObserver(token) }
        let call = expectLoaderCall("storefront reload")
        let settled = expectSettled("partial reload finished")
        storefront.yield()
        await fulfillment(of: [call], timeout: 2)
        loader.complete(with: .success(partialUSD))
        await fulfillment(of: [settled], timeout: 2)
        await fulfillment(of: [noPost], timeout: 0.2)
        XCTAssertEqual(service.catalogue.offers.count, 4)
        XCTAssertEqual(scaleStore.scale(for: usd), usdScale)
    }

    // MARK: - Foreground

    func testForegroundWithAHealthyCatalogueDoesNotReload() async {
        await seed(.success(fullUSD))
        XCTAssertEqual(scaleStore.scale(for: usd), usdScale)
        let noCall = expectNoLoaderCall("healthy catalogue must not hit StoreKit")
        postForeground()
        await fulfillment(of: [noCall], timeout: 0.5)
        XCTAssertEqual(loader.calls, 1)
    }

    func testForegroundAfterAFailedLoadReloads() async {
        // A good catalogue and scale first: only the failure makes it unhealthy.
        await seed(.success(fullUSD))
        await seed(.failure(OfflineError()))
        XCTAssertTrue(service.needsCatalogueReload)
        let call = expectLoaderCall("failed load retried on foreground")
        postForeground()
        await fulfillment(of: [call], timeout: 2)
        XCTAssertEqual(loader.calls, 3)
    }

    func testForegroundAfterAPartialLoadReloads() async {
        // The scale is cached already: only the missing pack makes it unhealthy.
        XCTAssertTrue(scaleStore.record(usdScale))
        await seed(.success(partialUSD))
        XCTAssertEqual(scaleStore.scale(for: usd), usdScale, "a partial catalogue keeps the stored scale")
        let call = expectLoaderCall("partial load retried on foreground")
        postForeground()
        await fulfillment(of: [call], timeout: 2)
        XCTAssertEqual(loader.calls, 2)
    }

    func testForegroundWithNoScaleForTheCatalogueCurrencyReloads() async {
        // A full catalogue whose prices give no scale (fewer than three distinct).
        await seed(.success(catalogue(["0.99", "0.99", "1.99", "1.99", "1.99"])))
        XCTAssertTrue(service.catalogue.isComplete)
        XCTAssertNil(scaleStore.scale(for: usd))
        let call = expectLoaderCall("missing scale retried on foreground")
        postForeground()
        await fulfillment(of: [call], timeout: 2)
        XCTAssertEqual(loader.calls, 2)
    }

    func testForegroundDuringAnInFlightLoadIsNotQueued() async {
        let first = expectLoaderCall("first load")
        storefront.yield()
        await fulfillment(of: [first], timeout: 2)
        postForeground()
        XCTAssertNil(service.queuedCatalogueReload, "a foreground mid-load queues nothing")
        let noFollowUp = expectNoLoaderCall("foreground mid-load adds nothing")
        let settled = expectSettled("failed load finished")
        loader.complete(with: .failure(OfflineError()))
        await fulfillment(of: [settled, noFollowUp], timeout: 0.5)
        XCTAssertEqual(loader.calls, 1)

        // The failure must not leave the in-flight flag stuck: the next foreground retries.
        XCTAssertFalse(service.isCatalogueReloadInFlight)
        let retry = expectLoaderCall("next foreground retries the failure")
        postForeground()
        await fulfillment(of: [retry], timeout: 2)
        XCTAssertEqual(loader.calls, 2)
    }

    // MARK: - Coalescing

    func testTwoTriggersDuringOneLoadScheduleExactlyOneFollowUp() async {
        let first = expectLoaderCall("first load")
        service.requestCatalogueReload(.storefrontChanged)
        await fulfillment(of: [first], timeout: 2)

        service.requestCatalogueReload(.storefrontChanged)
        service.requestCatalogueReload(.storefrontChanged)
        XCTAssertEqual(loader.calls, 1, "nothing starts while a load is in flight")

        let followUp = expectLoaderCall("one follow-up")
        loader.complete(with: .success(partialUSD))
        await fulfillment(of: [followUp], timeout: 2)

        let noThird = expectNoLoaderCall("no third load")
        loader.complete(with: .success(fullUSD))
        await fulfillment(of: [noThird], timeout: 0.5)
        XCTAssertEqual(loader.calls, 2)
        XCTAssertFalse(service.isCatalogueReloadInFlight)
    }

    // MARK: - Failure keeps the good state

    func testFailedReloadKeepsThePreviousCatalogueAndScale() async {
        await seed(.success(fullUSD))
        let (noPost, token) = expectNoScaleChange("a failed reload posts no scale change")
        defer { center.removeObserver(token) }

        // Storefront-triggered reload fails...
        let storefrontCall = expectLoaderCall("storefront reload")
        var settled = expectSettled("storefront reload finished")
        storefront.yield()
        await fulfillment(of: [storefrontCall], timeout: 2)
        loader.complete(with: .failure(OfflineError()))
        await fulfillment(of: [settled], timeout: 2)
        XCTAssertTrue(service.needsCatalogueReload, "the failure is retried on the next foreground")

        // ...and so does the foreground retry.
        let foregroundCall = expectLoaderCall("foreground retry")
        settled = expectSettled("foreground retry finished")
        postForeground()
        await fulfillment(of: [foregroundCall], timeout: 2)
        loader.complete(with: .failure(OfflineError()))
        await fulfillment(of: [settled], timeout: 2)

        await fulfillment(of: [noPost], timeout: 0.2)
        XCTAssertEqual(service.catalogue.offers.map(\.productID), StoreKitService.productIDs)
        XCTAssertEqual(scaleStore.scale(for: usd), usdScale)
        XCTAssertTrue(posterSpy.requests.isEmpty, "a reload failure is a silent retry, not a banner")
    }

    func testLaunchLoadFailureStillReportsToTheUser() async throws {
        loader.immediate = [.failure(OfflineError())]
        await service.loadProducts(.launch)
        XCTAssertEqual(posterSpy.requests.count, 1)
        let request = try XCTUnwrap(posterSpy.requests.first)
        XCTAssertEqual(request.content.body, Localized.text("deposit.error.products_load_failed"))
    }

    // MARK: - Lifetime

    func testDeinitStopsObservingBothTriggers() async {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let terminated = expectation(description: "storefront observation cancelled")
        continuation.onTermination = { _ in terminated.fulfill() }
        let loader = loader!
        var owned: StoreKitService? = StoreKitService(
            notificationPoster: LocalNotificationPosterSpy(), defaults: makeIsolatedDefaults(),
            priceScaleStore: scaleStore, catalogueLoader: { try await loader.load() },
            storefrontChanges: stream, foregroundCenter: center
        )
        weak var released = owned
        XCTAssertNotNil(released)
        service = nil
        owned = nil
        XCTAssertNil(released, "observers must not retain the service")
        await fulfillment(of: [terminated], timeout: 2)

        let noCall = expectNoLoaderCall("a released service reloads nothing")
        continuation.yield()
        postForeground()
        await fulfillment(of: [noCall], timeout: 0.5)
        XCTAssertEqual(loader.calls, 0)
    }
}
