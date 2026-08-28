import XCTest
@testable import SnoozePay

/// Coverage for `ReferralService.applyFriendCode` (#443): the format / self-apply
/// / already-applied rejections and the persist-then-credit rollback on a balance
/// lock — a money path that previously had only UI-copy tests. Each case uses an
/// isolated UserDefaults suite so the referral + ledger stores never touch shared
/// state.
final class ReferralServiceTests: XCTestCase {

    private var testDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "test.referral.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func makeService(balance: Double = 1000) -> ReferralService {
        testDefaults.set(balance, forKey: "user_balance")
        return ReferralService(
            defaults: testDefaults,
            balanceService: BalanceService(defaults: testDefaults, notificationCenter: NotificationCenter())
        )
    }

    private func promotions() -> [Transaction] {
        TransactionRepository(defaults: testDefaults).fetchAllOrFail().filter { $0.type == .promotion }
    }

    // MARK: - Rejections

    func testApply_invalidFormat_throws() {
        let service = makeService()
        XCTAssertThrowsError(try service.applyFriendCode("ABC")) { error in
            XCTAssertEqual(error as? ReferralService.ApplyError, .invalidFormat, "Too-short code")
        }
        // Six chars but contains an excluded glyph ("1") → still invalid.
        XCTAssertThrowsError(try service.applyFriendCode("ABCDE1")) { error in
            XCTAssertEqual(error as? ReferralService.ApplyError, .invalidFormat, "Excluded glyph")
        }
    }

    func testApply_ownCode_throwsCannotApplyOwnCode() {
        let service = makeService()
        let mine = service.getMyCode()   // generates + persists the user's own code
        XCTAssertThrowsError(try service.applyFriendCode(mine)) { error in
            XCTAssertEqual(error as? ReferralService.ApplyError, .cannotApplyOwnCode)
        }
    }

    func testApply_alreadyApplied_throws() {
        let service = makeService()
        XCTAssertEqual(try? service.applyFriendCode("ABCDEF"), ReferralService.referralBonusAmount)
        XCTAssertThrowsError(try service.applyFriendCode("XYZ234")) { error in
            XCTAssertEqual(error as? ReferralService.ApplyError, .alreadyApplied)
        }
    }

    // MARK: - Happy path

    func testApply_valid_creditsBonusOnceAndPersists() {
        let service = makeService(balance: 0)
        // Leading/trailing whitespace + lower-case must be normalised internally.
        let credited = try? service.applyFriendCode("  abcdef  ")
        XCTAssertEqual(credited, ReferralService.referralBonusAmount)
        XCTAssertEqual(service.appliedFriendCode, "ABCDEF")

        let recorded = promotions()
        XCTAssertEqual(recorded.count, 1, "Exactly one referral bonus must be credited")
        XCTAssertEqual(recorded.first?.amount, ReferralService.referralBonusAmount)
    }

    // MARK: - Balance-lock rollback

    func testApply_balanceLocked_rollsBackAppliedCode() {
        // A corrupt (negative) balance makes creditPromotion refuse. The apply
        // must roll back the persisted code so the user's one-shot referral slot
        // isn't consumed with no bonus to show for it.
        let service = makeService(balance: -5)
        XCTAssertThrowsError(try service.applyFriendCode("ABCDEF")) { error in
            XCTAssertEqual(error as? ReferralService.ApplyError, .balanceLocked)
        }
        XCTAssertNil(service.appliedFriendCode,
                     "A refused credit must roll back the applied code so the user can retry")
        XCTAssertTrue(promotions().isEmpty, "No bonus may be recorded when the credit was refused")
    }
}
