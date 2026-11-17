import XCTest
@testable import SnoozePay

/// #1126: the per-currency cache of storefront snooze-price scales.
final class SnoozePriceScaleStoreTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var center: NotificationCenter!
    private var store: SnoozePriceScaleStore!
    private var posts = 0
    private var token: NSObjectProtocol?

    private let usd = Currency(code: "USD")!
    private let eur = Currency(code: "EUR")!

    override func setUp() {
        super.setUp()
        suiteName = "test_\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        center = NotificationCenter()
        store = SnoozePriceScaleStore(defaults: defaults, notificationCenter: center)
        posts = 0
        token = center.addObserver(
            forName: SnoozePriceScaleStore.snoozePriceScaleChangedNotification, object: nil, queue: nil
        ) { [weak self] _ in self?.posts += 1 }
    }

    override func tearDown() {
        if let token { center.removeObserver(token) }
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func scale(_ currency: Currency, _ tiers: [String]) -> SnoozePriceScale {
        SnoozePriceScale(currency: currency, tiers: tiers.map { Decimal(string: $0)! })!
    }

    // MARK: - Round trip

    func testEmptyStoreHasNoScaleAndNoStorefront() {
        XCTAssertNil(store.scale(for: usd))
        XCTAssertNil(store.lastStorefrontCurrency)
    }

    func testRecordRoundTripsThroughAFreshStore() throws {
        let usdScale = scale(usd, ["0.99", "1.99", "2.99"])
        XCTAssertTrue(store.record(usdScale))
        XCTAssertEqual(posts, 1)

        let reopened = SnoozePriceScaleStore(defaults: defaults, notificationCenter: center)
        XCTAssertEqual(reopened.scale(for: usd), usdScale)
        XCTAssertEqual(reopened.lastStorefrontCurrency, usd)

        let all = try XCTUnwrap(defaults.dictionary(forKey: SnoozePriceScaleStore.scalesKey))
        let entry = try XCTUnwrap(all["USD"] as? [String: Any])
        XCTAssertEqual(entry[SnoozePriceScaleStore.tiersField] as? [String], ["0.99", "1.99", "2.99"])
        XCTAssertNotNil(entry[SnoozePriceScaleStore.updatedAtField] as? Date)
    }

    // MARK: - Corrupt values

    func testCorruptStoredValuesReadAsNil() {
        let cases: [(String, Any)] = [
            ("not a dictionary", "USD 0.99"),
            ("entry not a dictionary", ["USD": "0.99,1.99,2.99"]),
            ("tiers missing", ["USD": ["updatedAt": Date()]]),
            ("tiers not strings", ["USD": ["tiers": [0.99, 1.99, 2.99]]]),
            ("two tiers", ["USD": ["tiers": ["0.99", "1.99"]]]),
            ("descending", ["USD": ["tiers": ["2.99", "1.99", "0.99"]]]),
            ("trailing garbage", ["USD": ["tiers": ["0.99", "1.99x", "2.99"]]]),
            ("comma decimal", ["USD": ["tiers": ["0.99", "1,09", "2.99"]]])
        ]
        for (name, value) in cases {
            defaults.set(value, forKey: SnoozePriceScaleStore.scalesKey)
            XCTAssertNil(store.scale(for: usd), name)
        }
    }

    func testCorruptLastStorefrontCurrencyReadsAsNil() {
        for value: Any in ["us dollar", 840, ""] {
            defaults.set(value, forKey: SnoozePriceScaleStore.lastStorefrontCurrencyKey)
            XCTAssertNil(store.lastStorefrontCurrency, "\(value)")
        }
    }

    func testRecordOverwritesACorruptEntry() {
        defaults.set(["USD": ["tiers": ["junk"]]], forKey: SnoozePriceScaleStore.scalesKey)
        let usdScale = scale(usd, ["0.99", "1.99", "2.99"])
        XCTAssertTrue(store.record(usdScale))
        XCTAssertEqual(store.scale(for: usd), usdScale)
    }

    // MARK: - Change detection

    func testIdenticalRecordDoesNotWriteOrPost() throws {
        let usdScale = scale(usd, ["0.99", "1.99", "2.99"])
        XCTAssertTrue(store.record(usdScale))
        let stamped = try XCTUnwrap(defaults.dictionary(forKey: SnoozePriceScaleStore.scalesKey) as NSDictionary?)

        XCTAssertFalse(store.record(usdScale))
        XCTAssertEqual(posts, 1)
        XCTAssertEqual(defaults.dictionary(forKey: SnoozePriceScaleStore.scalesKey) as NSDictionary?, stamped,
                       "an identical record must not even bump updatedAt")
    }

    func testChangedTiersPostAgain() {
        XCTAssertTrue(store.record(scale(usd, ["0.99", "1.99", "2.99"])))
        XCTAssertTrue(store.record(scale(usd, ["1.29", "2.49", "3.99"])))
        XCTAssertEqual(posts, 2)
        XCTAssertEqual(store.scale(for: usd), scale(usd, ["1.29", "2.49", "3.99"]))
    }

    // MARK: - Per currency

    func testStorefrontBNeverOverwritesStorefrontA() {
        let usdScale = scale(usd, ["0.99", "1.99", "2.99"])
        let eurScale = scale(eur, ["1.09", "2.29", "3.49"])
        XCTAssertTrue(store.record(usdScale))
        XCTAssertTrue(store.record(eurScale))

        XCTAssertEqual(store.scale(for: usd), usdScale)
        XCTAssertEqual(store.scale(for: eur), eurScale)
    }

    func testLastStorefrontCurrencyFollowsTheLatestRecord() {
        let usdScale = scale(usd, ["0.99", "1.99", "2.99"])
        let steps: [(SnoozePriceScale, Currency, Bool)] = [
            (usdScale, usd, true),
            (scale(eur, ["1.09", "2.29", "3.49"]), eur, true),
            (usdScale, usd, true),    // same USD tiers, but the storefront moved back
            (usdScale, usd, false),
            (.rouble, .rub, true)
        ]
        for (index, (recorded, expected, changed)) in steps.enumerated() {
            XCTAssertEqual(store.record(recorded), changed, "step \(index)")
            XCTAssertEqual(store.lastStorefrontCurrency, expected, "step \(index)")
        }
        XCTAssertEqual(posts, 4)
    }

    // MARK: - Roubles

    func testRoubleScaleIsNeverStored() {
        XCTAssertTrue(store.record(.rouble))
        XCTAssertNil(defaults.object(forKey: SnoozePriceScaleStore.scalesKey))
        XCTAssertEqual(store.lastStorefrontCurrency, .rub)
        XCTAssertFalse(store.record(.rouble))
    }

    func testRoubleScaleIsTheConstantEvenOverAPlantedValue() {
        defaults.set(["RUB": ["tiers": ["49", "149", "299"]]], forKey: SnoozePriceScaleStore.scalesKey)
        XCTAssertEqual(store.scale(for: .rub), .rouble)
    }

    // MARK: - StoreKit seam

    /// The five real SKUs, cheapest first, priced as a US storefront.
    private let usdCatalogue: [(String, String)] = Array(zip(
        StoreKitService.productIDs, ["0.99", "1.99", "2.99", "4.99", "9.99"]
    ))

    private func offers(_ pairs: [(String, String)]) -> [TopUpOffer] {
        pairs.map {
            TopUpOffer(productID: $0.0, price: Decimal(string: $0.1)!, currencyCode: "USD", displayPrice: "$\($0.1)")!
        }
    }

    @MainActor
    func testOnlyAFullRealCatalogueYieldsAScaleToRecord() {
        struct Case {
            let name: String, pairs: [(String, String)], isDemo: Bool, expected: SnoozePriceScale?
        }
        let full = usdCatalogue
        let cheapest3 = scale(usd, ["0.99", "1.99", "2.99"])
        let cases: [Case] = [
            Case(name: "5/5", pairs: full, isDemo: false, expected: cheapest3),
            Case(name: "5/5 shuffled", pairs: full.reversed(), isDemo: false, expected: cheapest3),
            Case(name: "demo catalogue", pairs: full, isDemo: true, expected: nil),
            Case(name: "forced-empty catalogue", pairs: [], isDemo: false, expected: nil),
            Case(name: "4/5 missing the cheapest", pairs: Array(full.dropFirst()), isDemo: false, expected: nil),
            Case(name: "4/5 missing the dearest", pairs: Array(full.dropLast()), isDemo: false, expected: nil),
            Case(name: "duplicate product ID", pairs: Array(full.dropLast()) + [full[0]], isDemo: false, expected: nil),
            Case(name: "6 offers, one duplicated", pairs: full + [full[0]], isDemo: false, expected: nil),
            Case(name: "foreign product ID", pairs: Array(full.dropLast()) + [("io.example.other", "9.99")],
                 isDemo: false, expected: nil)
        ]
        for testCase in cases {
            XCTAssertEqual(StoreKitService.scaleToRecord(from: offers(testCase.pairs), isDemo: testCase.isDemo),
                           testCase.expected, testCase.name)
        }
    }

    @MainActor
    func testPartialCatalogueKeepsTheStoredScale() {
        let stored = scale(usd, ["0.99", "1.99", "2.99"])
        XCTAssertTrue(store.record(stored))
        let partial = offers(Array(usdCatalogue.dropFirst()))
        if let shifted = StoreKitService.scaleToRecord(from: partial, isDemo: false) {
            XCTFail("partial catalogue must not yield a scale, got \(shifted)")
            _ = store.record(shifted)
        }
        XCTAssertEqual(store.scale(for: usd), stored)
        XCTAssertEqual(posts, 1)
    }
}
