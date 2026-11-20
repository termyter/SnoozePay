import XCTest
@testable import SnoozePay

/// #1204: a StoreKit failure about a paid transaction that no screen subscribes
/// to used to reach only the notification banner, and since #472 the app does
/// not ask for the permission that banner needs. It is now also kept in
/// `CriticalWarningCenter` until OK, the way #871 keeps a lost snooze.
///
/// The two failure sites in `handle(transactionResult:)` (unverified, unknown
/// product) need a `StoreKit.Transaction`, which a unit test cannot build; the
/// four reached through `applyVerifiedPurchase` are pinned here.
@MainActor
final class StoreKitUnclaimedFailureWarningTests: XCTestCase {
    private let usd = Currency(code: "USD")!
    private var defaults: UserDefaults!
    private var balance: BalanceService!
    private var warnings: CriticalWarningCenter!
    private var poster: LocalNotificationPosterSpy!
    private var store: StoreKitService!

    override func setUp() {
        super.setUp()
        defaults = makeIsolatedDefaults()
        launch()
    }

    override func tearDown() {
        store = nil
        warnings = nil
        poster = nil
        balance = nil
        defaults = nil
        super.tearDown()
    }

    /// A fresh process over `defaults`, on a device that refuses the banner
    /// (no notification permission). The warning queue is read back from disk.
    private func launch() {
        warnings = CriticalWarningCenter(defaults: defaults)
        warnings.isForegroundActive = { false } // Never present over the test host.
        poster = LocalNotificationPosterSpy()
        poster.addError = NSError(domain: "UNErrorDomain", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "Notifications are not allowed"])
        store = StoreKitService(notificationPoster: poster, defaults: defaults, criticalWarnings: warnings)
        balance = BalanceService(defaults: defaults, notificationCenter: NotificationCenter())
    }

    /// The ledger cannot be read, so a credit is `.notRecorded`: Apple has the money.
    private func lockLedger() {
        defaults.set(Data("unreadable ledger".utf8), forKey: "stored_transactions")
        balance = BalanceService(defaults: defaults, notificationCenter: NotificationCenter())
    }

    private func paid(_ transactionID: UInt64 = 7, currency: Currency? = .rub) -> RestorableTopUp {
        RestorableTopUp(transactionID: transactionID, productID: "io.mobilife.snoozepay.balance.299",
                        currency: currency, transactionPrice: 299,
                        purchaseDate: Date(timeIntervalSince1970: 1_700_000_000))
    }

    private func apply(_ purchase: RestorableTopUp) async -> Int {
        var finishes = 0
        await store.applyVerifiedPurchase(purchase, balance: balance) { finishes += 1 }
        return finishes
    }

    /// The issue's case: an approval arrives with no screen mounted, the credit
    /// is not recorded, and the banner is refused. The user still gets the
    /// failure's own copy in-app, and it survives a relaunch.
    func testUnclaimedUnrecordedCredit_keepsAPersistedWarningWithTheFailureCopy() async throws {
        lockLedger()

        let finishes = await apply(paid())

        XCTAssertEqual(finishes, 0, "precondition: the credit was refused and the transaction left unfinished")
        XCTAssertEqual(poster.requests.count, 1, "the banner is still tried, as #871 does")
        XCTAssertEqual(warnings.pending.count, 1)
        let warning = try XCTUnwrap(warnings.pending.first)
        XCTAssertEqual(warning.cause, .purchaseFailed)
        XCTAssertEqual(warning.transactionID, "7")
        XCTAssertEqual(warning.title, Localized.text("deposit.notification.failed.title"))
        XCTAssertEqual(warning.message, Localized.text("deposit.error.credit_failed"))
        XCTAssertEqual(CriticalWarningCenter(defaults: defaults).pending, warnings.pending,
                       "persisted before any presentation")
    }

    /// Each refusal reached through `applyVerifiedPurchase` keeps a warning
    /// named after its transaction, with its own copy.
    func testEveryReachableRefusal_keepsAWarningForItsTransaction() async {
        _ = await apply(paid(1, currency: nil)) // invalid paid metadata
        _ = balance.freezeCurrency(.rub)
        _ = await apply(paid(2, currency: usd)) // paid in another currency
        defaults.set(["unexpected": 7], forKey: "storekit.processed_tx_ids")
        _ = await apply(paid(3)) // dedup table unreadable
        defaults.removeObject(forKey: "storekit.processed_tx_ids")
        lockLedger()
        _ = await apply(paid(4)) // credit not recorded

        XCTAssertEqual(warnings.pending.map(\.transactionID), ["1", "2", "3", "4"])
        XCTAssertEqual(warnings.pending.map(\.message), [
            Localized.text("deposit.error.credit_failed"), Localized.text("deposit.error.foreign_currency"),
            Localized.text("deposit.error.dedup_degraded"), Localized.text("deposit.error.credit_failed")
        ])
        XCTAssertEqual(poster.requests.count, 4, "every refusal still tries its banner")
    }

    /// A mounted screen shows its own alert; a warning on top would say it twice.
    func testClaimedFailure_recordsNoWarning() async {
        lockLedger()
        store.beginObservingPurchaseFeedback()
        var broadcast: [String] = []
        let token = NotificationCenter.default.addObserver(
            forName: StoreKitService.purchaseFailedNotification, object: store, queue: nil
        ) { note in
            broadcast.append(note.userInfo?[StoreKitService.messageUserInfoKey] as? String ?? "")
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let finishes = await apply(paid())

        XCTAssertEqual(finishes, 0)
        XCTAssertEqual(broadcast, [Localized.text("deposit.error.credit_failed")], "the screen got the failure")
        XCTAssertTrue(warnings.pending.isEmpty, "the subscribed screen shows its own alert")
        XCTAssertTrue(poster.requests.isEmpty)
    }

    /// The transaction stays unfinished and replays in the same process and on
    /// every launch: one pending warning for it, not one per replay. Another
    /// transaction still gets its own, and an acknowledged one comes back while
    /// the money is still not credited.
    func testReplayedFailure_keepsOneWarningPerTransaction() async throws {
        lockLedger()
        _ = await apply(paid())
        _ = await apply(paid())
        launch() // The ledger is still unreadable.
        _ = await apply(paid())
        XCTAssertEqual(warnings.pending.map(\.transactionID), ["7"])

        _ = await apply(paid(8))
        XCTAssertEqual(warnings.pending.map(\.transactionID), ["7", "8"], "dedup is per transaction")

        warnings.acknowledge(try XCTUnwrap(warnings.pending.first).id)
        _ = await apply(paid())
        XCTAssertEqual(warnings.pending.map(\.transactionID), ["8", "7"])
    }

    /// Completions stay on the best-effort banner (#45): nothing to warn about.
    func testUnclaimedCompletion_postsOnlyTheBanner() async {
        let finishes = await apply(paid())

        XCTAssertEqual(finishes, 1, "precondition: credited")
        XCTAssertEqual(poster.requests.map(\.content.title), [Localized.text("deposit.notification.credited.title")])
        XCTAssertTrue(warnings.pending.isEmpty)
    }

    /// A failure with no transaction charged nothing (here the launch catalogue
    /// load), so it stays on the banner and never becomes a modal warning.
    func testFailureWithoutATransaction_postsOnlyTheBanner() {
        store.postPurchaseFailed(Localized.text("deposit.error.products_load_failed"))

        XCTAssertEqual(poster.requests.count, 1)
        XCTAssertTrue(warnings.pending.isEmpty)
    }
}
