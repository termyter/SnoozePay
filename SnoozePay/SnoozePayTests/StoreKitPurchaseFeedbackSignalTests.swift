import XCTest
@testable import SnoozePay

/// #1104: what the user is told on the purchase replay and refusal branches.
/// The money tests (`StoreKitPurchaseCrashRecoveryTests`,
/// `StoreKitVerifiedPurchaseTests`) pin finishes, rows and markers; these pin
/// the feedback — a second toast for one payment, or silence after Apple took
/// the money, both leave the money assertions green.
@MainActor
final class StoreKitPurchaseFeedbackSignalTests: XCTestCase {
    private let usd = Currency(code: "USD")!
    private var suites: [String] = []
    private var recorders: [FeedbackRecorder] = []
    private let paid = RestorableTopUp(transactionID: 7, productID: "io.mobilife.snoozepay.balance.299",
                                       currency: Currency(code: "USD"), transactionPrice: 2.99,
                                       purchaseDate: Date(timeIntervalSince1970: 1_700_000_000))

    override func tearDown() {
        recorders = [] // each recorder detaches itself in deinit
        suites.forEach { UserDefaults().removePersistentDomain(forName: $0) }
        suites = []
        super.tearDown()
    }

    private func makeDefaults() -> UserDefaults {
        let name = "StoreKitPurchaseFeedbackSignalTests.\(UUID())"
        suites.append(name)
        return UserDefaults(suiteName: name)!
    }

    private struct Process {
        let balance: BalanceService
        let store: StoreKitService
        let poster: LocalNotificationPosterSpy
        let feedback: FeedbackRecorder
    }

    /// A fresh process over `defaults`. With `screenMounted` a top-up screen is
    /// subscribed, so feedback is an in-app broadcast; without it, a banner.
    private func launch(_ defaults: UserDefaults, screenMounted: Bool = true) -> Process {
        let poster = LocalNotificationPosterSpy()
        let store = StoreKitService(notificationPoster: poster, defaults: defaults)
        if screenMounted { store.beginObservingPurchaseFeedback() }
        let feedback = FeedbackRecorder(store: store)
        recorders.append(feedback)
        return Process(balance: BalanceService(defaults: defaults, notificationCenter: NotificationCenter()),
                       store: store, poster: poster, feedback: feedback)
    }

    /// The same payment in roubles: the currency an unreadable (hence not
    /// pristine) wallet still accepts, so the credit reaches the ledger write.
    private var paidInRoubles: RestorableTopUp {
        RestorableTopUp(transactionID: 7, productID: paid.productID, currency: .rub,
                        transactionPrice: 2.99, purchaseDate: paid.purchaseDate)
    }

    private func apply(_ process: Process, _ purchase: RestorableTopUp? = nil, times: Int = 1) async -> Int {
        var finishes = 0
        for _ in 0..<times {
            await process.store.applyVerifiedPurchase(purchase ?? paid, balance: process.balance) { finishes += 1 }
        }
        return finishes
    }

    // MARK: - Replays

    /// The credit row landed, the process died before mark/finish. The replay
    /// lands on `.alreadyCredited`: it finishes, and must not announce a
    /// second top-up — the user already saw the first (or will see the money).
    func testReplayOfAnAlreadyCreditedRowAnnouncesNothing() async {
        let defaults = makeDefaults()
        let first = launch(defaults)
        XCTAssertEqual(first.balance.topUpFromPurchase(amount: 2.99, currency: usd, ledgerID: paid.ledgerRowID),
                       .credited)

        let relaunched = launch(defaults)
        let finishes = await apply(relaunched)

        XCTAssertEqual(finishes, 1)
        XCTAssertEqual(relaunched.feedback.completed, [], "One payment, one toast — the replay is silent")
        XCTAssertEqual(relaunched.feedback.failed, [])
        XCTAssertTrue(relaunched.poster.requests.isEmpty)
    }

    /// Same state with no screen mounted: the replay must not fall back to a
    /// "Balance topped up" banner either.
    func testBackgroundReplayOfAnAlreadyCreditedRowPostsNoBanner() async {
        let defaults = makeDefaults()
        XCTAssertEqual(launch(defaults).balance.topUpFromPurchase(amount: 2.99, currency: usd,
                                                                  ledgerID: paid.ledgerRowID), .credited)

        let relaunched = launch(defaults, screenMounted: false)
        let finishes = await apply(relaunched)

        XCTAssertEqual(finishes, 1)
        XCTAssertTrue(relaunched.poster.requests.isEmpty, "A replay must not banner a second credit")
    }

    /// Three deliveries in one process plus one after a relaunch: exactly one
    /// "topped up" for the whole payment, carrying the paid amount.
    func testRepeatedReplaysAnnounceTheCreditExactlyOnce() async {
        let defaults = makeDefaults()
        let first = launch(defaults)
        var finishes = await apply(first, times: 3)
        let relaunched = launch(defaults)
        finishes += await apply(relaunched)

        XCTAssertEqual(finishes, 4)
        XCTAssertEqual(first.feedback.completed + relaunched.feedback.completed, [2.99])
        XCTAssertEqual(first.feedback.failed + relaunched.feedback.failed, [])
    }

    // MARK: - Refusals

    /// Credit landed, then the dedup table drifted: the purchase is refused,
    /// and the user is told why — once per attempt, never as a success.
    func testDegradedDedupRefusalTellsTheUser() async {
        let defaults = makeDefaults()
        let process = launch(defaults)
        XCTAssertEqual(process.balance.topUpFromPurchase(amount: 2.99, currency: usd, ledgerID: paid.ledgerRowID),
                       .credited)
        defaults.set(["unexpected": 7], forKey: "storekit.processed_tx_ids")

        let finishes = await apply(process)

        XCTAssertEqual(finishes, 0)
        XCTAssertEqual(process.feedback.failed, [StoreKitService.degradedDedupFailureMessage])
        XCTAssertEqual(process.feedback.completed, [])
    }

    /// The ledger is unreadable, so the credit is `.notRecorded`: Apple has the
    /// money and the transaction stays unfinished. Every attempt must say so
    /// now, not leave the user waiting for a later launch.
    func testUnrecordedCreditTellsTheUserOnEveryAttempt() async {
        let defaults = makeDefaults()
        defaults.set(Data("unreadable ledger".utf8), forKey: "stored_transactions")
        let process = launch(defaults)

        let finishes = await apply(process, paidInRoubles, times: 2)

        XCTAssertEqual(finishes, 0)
        XCTAssertEqual(process.feedback.failed, Array(repeating: StoreKitService.ledgerLockedFailureMessage, count: 2))
        XCTAssertEqual(process.feedback.completed, [])
    }

    /// The same unreadable ledger with a non-rouble payment never reaches the
    /// ledger write: an unreadable wallet is not pristine, so it is treated as
    /// a legacy rouble wallet and refused as `.refusedCurrency`. Pinned here:
    /// the user is told it failed, every attempt, never that it succeeded.
    /// The wording is deliberately not pinned — today it is the foreign-currency
    /// copy, which misnames the cause (reported on #1104's PR).
    func testUnreadableLedgerWithNonRoublePaymentStillTellsTheUser() async {
        let defaults = makeDefaults()
        defaults.set(Data("unreadable ledger".utf8), forKey: "stored_transactions")
        let process = launch(defaults)

        let finishes = await apply(process, times: 2)

        XCTAssertEqual(finishes, 0)
        XCTAssertEqual(process.feedback.failed.count, 2)
        XCTAssertFalse(process.feedback.failed.contains(""), "A refusal carries a message")
        XCTAssertEqual(process.feedback.completed, [])
    }

    /// Both refusals with no screen mounted (a deferred Ask-to-Buy approval or
    /// a launch replay): the message reaches the user as a failure banner.
    func testRefusalsWithoutAScreenFallBackToAFailureBanner() async throws {
        let degraded = makeDefaults()
        degraded.set(["unexpected": 7], forKey: "storekit.processed_tx_ids")
        let unrecorded = makeDefaults()
        unrecorded.set(Data("unreadable ledger".utf8), forKey: "stored_transactions")
        let cases = [(degraded, paid, StoreKitService.degradedDedupFailureMessage),
                     (unrecorded, paidInRoubles, StoreKitService.ledgerLockedFailureMessage)]

        for (defaults, purchase, message) in cases {
            let process = launch(defaults, screenMounted: false)
            let finishes = await apply(process, purchase)

            XCTAssertEqual(finishes, 0, message)
            XCTAssertEqual(process.poster.requests.count, 1, message)
            let banner = try XCTUnwrap(process.poster.requests.first, message)
            XCTAssertEqual(banner.content.title, Localized.text("deposit.notification.failed.title"))
            XCTAssertEqual(banner.content.body, message)
            XCTAssertNil(banner.trigger, "Feedback is immediate")
            XCTAssertEqual(process.feedback.failed, [], "No screen, no broadcast — the banner is the signal")
        }
    }
}

/// Records the in-app purchase feedback one store broadcasts on `.default`,
/// filtered by sender so a parallel or leftover store cannot leak in.
@MainActor
private final class FeedbackRecorder: NSObject {
    private(set) var completed: [Double] = []
    private(set) var failed: [String] = []

    init(store: StoreKitService) {
        super.init()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(didComplete(_:)),
                           name: StoreKitService.purchaseCompletedNotification, object: store)
        center.addObserver(self, selector: #selector(didFail(_:)),
                           name: StoreKitService.purchaseFailedNotification, object: store)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func didComplete(_ note: Notification) {
        completed.append(note.userInfo?[StoreKitService.amountUserInfoKey] as? Double ?? -1)
    }

    @objc private func didFail(_ note: Notification) {
        failed.append(note.userInfo?[StoreKitService.messageUserInfoKey] as? String ?? "<no message>")
    }
}
