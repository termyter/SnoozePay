import XCTest
@testable import SnoozePay

/// #548 — the firing-time top-up sheet may not promise a snooze count it did
/// not derive from the live price.
///
/// The sheet shipped the design comp's literals («+1 откладывание · ровно на
/// сейчас» over the 149 ₽ SKU) while the snooze price is user-set, so the claim
/// held at exactly 149 ₽ and nowhere else. The 200 ₽ case is the expensive one:
/// the user pays mid-alarm and still cannot snooze.
///
/// These tests pin the three rows of that table plus the boundaries the copy
/// has to survive: price == tier, price above the priciest SKU, price 1 ₽, and
/// a price the copy cannot use at all (free alarm).
@MainActor
final class FiringTopUpCopyTests: XCTestCase {

    /// The lineup the sheet actually offers, cheapest first.
    private let tiers = [149, 499, 999]

    // MARK: - The three cases from the issue

    /// 50 ₽ (the default price): 149 ₽ buys two snoozes, and the copy says two
    /// — not the old flat «+1 откладывание».
    func testDefaultPrice_149Tier_promisesTwoSnoozes() {
        XCTAssertEqual(FiringTopUpCopy.affordableSnoozes(topUp: 149, balance: 0, price: 50), 2)
        XCTAssertEqual(
            FiringTopUpCopy.rowTitle(topUp: 149, balance: 0, price: 50),
            "+2 откладывания"
        )
        XCTAssertTrue(FiringTopUpCopy.isSufficient(topUp: 149, balance: 0, price: 50))
    }

    /// 149 ₽: the one price at which the old literal was true. It stays true.
    func testPriceEqualToTier_promisesExactlyOneSnooze() {
        XCTAssertEqual(FiringTopUpCopy.affordableSnoozes(topUp: 149, balance: 0, price: 149), 1)
        XCTAssertEqual(
            FiringTopUpCopy.rowTitle(topUp: 149, balance: 0, price: 149),
            "+1 откладывание"
        )
    }

    /// 200 ₽ — the case that costs the user money. The 149 ₽ tier buys nothing,
    /// says so, and names the exact shortfall instead of «ровно на сейчас».
    func testPriceAboveCheapestTier_marksTierAsInsufficient() {
        XCTAssertEqual(FiringTopUpCopy.affordableSnoozes(topUp: 149, balance: 0, price: 200), 0)
        XCTAssertFalse(FiringTopUpCopy.isSufficient(topUp: 149, balance: 0, price: 200))
        XCTAssertEqual(
            FiringTopUpCopy.rowTitle(topUp: 149, balance: 0, price: 200),
            "Не хватит на откладывание"
        )
        XCTAssertEqual(FiringTopUpCopy.shortfall(topUp: 149, balance: 0, price: 200), 51)
        XCTAssertEqual(
            FiringTopUpCopy.rowHint(topUp: 149, balance: 0, price: 200),
            "не хватает \(MoneyFormatter.string(51))"
        )
    }

    /// The regression in one assertion: at 200 ₽ nothing on the sheet may read
    /// like the old literal.
    func testPriceAboveCheapestTier_noRowClaimsASnoozeItCannotDeliver() {
        for tier in tiers {
            let title = FiringTopUpCopy.rowTitle(topUp: tier, balance: 0, price: 200)
            let claimsSnooze = title.hasPrefix("+")
            XCTAssertEqual(
                claimsSnooze,
                FiringTopUpCopy.isSufficient(topUp: tier, balance: 0, price: 200),
                "tier \(tier) title «\(title)» must promise a snooze only when it buys one"
            )
        }
    }

    // MARK: - Pre-selection

    /// The sheet opens on the cheapest tier that unlocks a snooze. At 200 ₽
    /// that is 499 ₽, not the 149 ₽ the comp pre-selected.
    func testRecommendedAmount_isCheapestSufficientTier() {
        XCTAssertEqual(FiringTopUpCopy.recommendedAmount(from: tiers, balance: 0, price: 50), 149)
        XCTAssertEqual(FiringTopUpCopy.recommendedAmount(from: tiers, balance: 0, price: 149), 149)
        XCTAssertEqual(FiringTopUpCopy.recommendedAmount(from: tiers, balance: 0, price: 200), 499)
        XCTAssertEqual(FiringTopUpCopy.recommendedAmount(from: tiers, balance: 0, price: 500), 999)
    }

    /// Order of the supplied lineup must not change the answer.
    func testRecommendedAmount_ignoresInputOrder() {
        XCTAssertEqual(
            FiringTopUpCopy.recommendedAmount(from: [999, 149, 499], balance: 0, price: 200),
            499
        )
    }

    /// Nothing to recommend from an empty lineup — and no invented amount.
    func testRecommendedAmount_isNilForEmptyLineup() {
        XCTAssertNil(FiringTopUpCopy.recommendedAmount(from: [], balance: 0, price: 200))
        XCTAssertEqual(FiringTopUpCopy.subtitle(amounts: [], balance: 0, price: 200), "")
    }

    // MARK: - Boundaries

    /// A price above the priciest SKU: every tier is flagged, the largest is
    /// still offered (it gets the user closest), and the subtitle admits that
    /// one purchase will not be enough.
    func testPriceAboveEveryTier_flagsAllAndAdmitsItInTheSubtitle() {
        for tier in tiers {
            XCTAssertFalse(
                FiringTopUpCopy.isSufficient(topUp: tier, balance: 0, price: 1200),
                "tier \(tier) cannot cover a 1200 ₽ snooze"
            )
        }
        XCTAssertEqual(FiringTopUpCopy.recommendedAmount(from: tiers, balance: 0, price: 1200), 999)
        let subtitle = FiringTopUpCopy.subtitle(amounts: tiers, balance: 0, price: 1200)
        XCTAssertTrue(subtitle.contains(MoneyFormatter.string(1200)), subtitle)
        XCTAssertTrue(subtitle.contains(MoneyFormatter.string(999)), subtitle)
        XCTAssertTrue(subtitle.contains("не хватит"), subtitle)
    }

    /// 1 ₽ — the floor `PenaltyCell` allows. Big counts must pluralise as
    /// «откладываний», which is why this delegates to `SnoozeAffordability`.
    func testPriceOfOneRouble_countsAndPluralisesCorrectly() {
        XCTAssertEqual(FiringTopUpCopy.affordableSnoozes(topUp: 149, balance: 0, price: 1), 149)
        XCTAssertEqual(
            FiringTopUpCopy.rowTitle(topUp: 149, balance: 0, price: 1),
            "+149 откладываний"
        )
        XCTAssertEqual(
            FiringTopUpCopy.rowTitle(topUp: 999, balance: 0, price: 1),
            "+999 \(SnoozeAffordability.snoozeWord(for: 999))"
        )
    }

    /// Fractional coverage is floored — 499 ₽ at 200 ₽ is two snoozes and
    /// 99 ₽ of change, never "two and a half".
    func testCountIsFlooredNeverRounded() {
        XCTAssertEqual(FiringTopUpCopy.affordableSnoozes(topUp: 499, balance: 0, price: 200), 2)
        XCTAssertEqual(FiringTopUpCopy.affordableSnoozes(topUp: 999, balance: 0, price: 200), 4)
    }

    // MARK: - Balance participates

    /// The user's question is «can I snooze after paying», so money already in
    /// the wallet counts: 100 ₽ banked turns the 149 ₽ tier sufficient at a
    /// 200 ₽ price.
    func testExistingBalanceCanMakeACheapTierSufficient() {
        XCTAssertTrue(FiringTopUpCopy.isSufficient(topUp: 149, balance: 100, price: 200))
        XCTAssertEqual(FiringTopUpCopy.affordableSnoozes(topUp: 149, balance: 100, price: 200), 1)
        XCTAssertEqual(
            FiringTopUpCopy.rowTitle(topUp: 149, balance: 100, price: 200),
            "+1 откладывание"
        )
        XCTAssertEqual(FiringTopUpCopy.recommendedAmount(from: tiers, balance: 100, price: 200), 149)
    }

    /// A corrupt ledger (negative / non-finite) must never inflate a promise.
    func testCorruptBalanceIsTreatedAsZero() {
        XCTAssertEqual(FiringTopUpCopy.affordableSnoozes(topUp: 149, balance: -500, price: 200), 0)
        XCTAssertEqual(FiringTopUpCopy.affordableSnoozes(topUp: 149, balance: .nan, price: 200), 0)
        XCTAssertEqual(
            FiringTopUpCopy.affordableSnoozes(topUp: 149, balance: .infinity, price: 200),
            0
        )
    }

    // MARK: - No usable price

    /// A free alarm (0 ₽) or a corrupt price leaves nothing to derive from, so
    /// the copy drops every count claim rather than substituting a default —
    /// substituting one is the bug this file exists to prevent.
    func testUnusablePrice_degradesToPriceFreeCopy() {
        for price in [0, -50, Double.nan] {
            XCTAssertNil(FiringTopUpCopy.usablePrice(price))
            XCTAssertEqual(
                FiringTopUpCopy.rowTitle(topUp: 149, balance: 0, price: price),
                "Пополнить баланс"
            )
            XCTAssertEqual(FiringTopUpCopy.rowHint(topUp: 149, balance: 0, price: price), "")
            XCTAssertTrue(
                FiringTopUpCopy.isSufficient(topUp: 149, balance: 0, price: price),
                "with no price to fail against, no tier may be flagged"
            )
            XCTAssertEqual(
                FiringTopUpCopy.recommendedAmount(from: tiers, balance: 0, price: price),
                149
            )
            XCTAssertEqual(
                FiringTopUpCopy.subtitle(amounts: tiers, balance: 0, price: price),
                "Самое маленькое пополнение — \(MoneyFormatter.string(149)). "
                    + "Можно больше, чтобы не возвращаться сюда."
            )
        }
    }

    // MARK: - Subtitle

    /// The replaced line said «Минимум — 149 ₽ на следующее откладывание»: the
    /// cheapest SKU dressed up as the amount a snooze needs. The new subtitle
    /// quotes the price itself, and at 50 ₽ it no longer implies 149 ₽ is what
    /// a snooze costs.
    func testSubtitle_quotesThePriceNotTheCheapestSKU() {
        let subtitle = FiringTopUpCopy.subtitle(amounts: tiers, balance: 0, price: 50)
        XCTAssertTrue(subtitle.contains(MoneyFormatter.string(50)), subtitle)
        XCTAssertFalse(subtitle.contains("Минимум"), subtitle)
    }

    /// When the cheapest tier is not enough, the subtitle names the first one
    /// that is — the same amount the sheet pre-selects.
    func testSubtitle_namesTheFirstSufficientTier() {
        let subtitle = FiringTopUpCopy.subtitle(amounts: tiers, balance: 0, price: 200)
        XCTAssertTrue(subtitle.contains(MoneyFormatter.string(200)), subtitle)
        XCTAssertTrue(subtitle.contains("начиная с \(MoneyFormatter.string(499))"), subtitle)
    }

    // MARK: - Wiring to the real lineup

    /// The copy is exercised against the SKUs the sheet actually renders, so a
    /// future lineup change (#240) is measured by these tests rather than
    /// sliding past them.
    func testRealDefaultPresets_at200Rubles_preselectA499Tier() {
        let amounts = FiringTopUpBottomSheetViewController.defaultPresets.map(\.amount)
        XCTAssertEqual(amounts.sorted(), [149, 499, 999])
        XCTAssertEqual(FiringTopUpCopy.recommendedAmount(from: amounts, balance: 0, price: 200), 499)
        XCTAssertFalse(FiringTopUpCopy.isSufficient(topUp: amounts.min() ?? 0, balance: 0, price: 200))
    }
}
