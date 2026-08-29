import Foundation

/// Copy math for the firing-time top-up sheet
/// (`FiringTopUpBottomSheetViewController`) — #548.
///
/// Every claim the sheet makes about a top-up tier is derived here from two
/// live numbers: the price of the NEXT snooze (`AlarmFiringViewModel
/// .currentPenalty`, i.e. the progressive rung the user is about to pay) and
/// the wallet balance the purchase lands on top of. Nothing in this file
/// invents a snooze count.
///
/// ## Why the previous copy was wrong
///
/// The sheet shipped static labels lifted from the design comp — «+1
/// откладывание · ровно на сейчас» over the 149 ₽ SKU — while the snooze price
/// is user-set (`PenaltyCell` accepts anything from 1 ₽, default 50 ₽). The
/// claim was therefore true only at exactly 149 ₽:
///
/// | price | 149 ₽ tier promised | reality |
/// |---|---|---|
/// | 50 ₽ | «+1 откладывание» | buys 2 |
/// | 149 ₽ | «+1 откладывание» | correct |
/// | 200 ₽ | «+1 откладывание · ровно на сейчас» | buys **0** |
///
/// The third row is the one that costs money: the user pays mid-alarm and
/// still cannot snooze. So a tier that does not unlock a single snooze is
/// labelled as such (`rowTitle` → «Не хватит на откладывание», plus the exact
/// shortfall in `rowHint`), and `recommendedAmount(from:balance:price:)`
/// pre-selects the cheapest tier that *does*.
///
/// ## Balance is part of the arithmetic
///
/// The question the user has is «can I snooze after this purchase», not «is
/// this SKU bigger than the price». With 100 ₽ already in the wallet a 149 ₽
/// top-up does unlock a 200 ₽ snooze, and the copy says so.
///
/// Pluralisation is delegated to `SnoozeAffordability.snoozeWord(for:)` (#546)
/// rather than re-derived — that helper is already the single source for
/// «откладывание / откладывания / откладываний» on the balance cards.
enum FiringTopUpCopy {

    /// The price the copy is allowed to reason about, or `nil` when there is
    /// nothing to reason about: a free alarm (0 ₽) or a corrupt non-finite
    /// value. In that case the sheet degrades to price-free wording instead of
    /// substituting a default — a made-up 50 ₽ here would be the same class of
    /// bug this file exists to remove.
    static func usablePrice(_ price: Double) -> Double? {
        guard price.isFinite, price > 0 else { return nil }
        return price
    }

    /// Wallet balance, sanitised: negative or non-finite ledgers count as 0 so
    /// a corrupt balance can never inflate a promised snooze count.
    private static func usableBalance(_ balance: Double) -> Double {
        guard balance.isFinite, balance > 0 else { return 0 }
        return balance
    }

    /// How many snoozes the wallet buys once `amount` is credited. Floored —
    /// the sheet never advertises a fractional snooze — and 0 when the top-up
    /// still leaves the user short.
    static func affordableSnoozes(topUp amount: Int, balance: Double, price: Double) -> Int {
        guard let price = usablePrice(price) else { return 0 }
        let total = usableBalance(balance) + Double(max(0, amount))
        return Int(floor(total / price))
    }

    /// `true` when buying this tier unlocks at least one snooze. An unknown or
    /// free price has nothing to fail against, so nothing is flagged.
    static func isSufficient(topUp amount: Int, balance: Double, price: Double) -> Bool {
        guard usablePrice(price) != nil else { return true }
        return affordableSnoozes(topUp: amount, balance: balance, price: price) >= 1
    }

    /// Roubles still missing for one snooze after buying this tier. 0 once the
    /// tier is sufficient.
    static func shortfall(topUp amount: Int, balance: Double, price: Double) -> Double {
        guard let price = usablePrice(price) else { return 0 }
        return max(0, price - (usableBalance(balance) + Double(max(0, amount))))
    }

    /// Tier row title — «+2 откладывания» when the purchase unlocks snoozes,
    /// «Не хватит на откладывание» when it does not.
    static func rowTitle(topUp amount: Int, balance: Double, price: Double) -> String {
        guard usablePrice(price) != nil else {
            return Localized.text("firing.top_up.row.title.generic")
        }
        let count = affordableSnoozes(topUp: amount, balance: balance, price: price)
        guard count > 0 else {
            return Localized.text("firing.top_up.row.title.insufficient")
        }
        // Count and noun travel together in one entry: «+2 откладывания» puts
        // the number first, «2 more snoozes» does not, and only the catalogue
        // can know which.
        return Localized.format(
            "firing.top_up.row.title.snoozes",
            count,
            SnoozeAffordability.snoozeWord(for: count)
        )
    }

    /// Tier row hint — the price the count was divided by, or the exact
    /// shortfall when the tier buys nothing.
    static func rowHint(topUp amount: Int, balance: Double, price: Double) -> String {
        guard let price = usablePrice(price) else { return "" }
        if isSufficient(topUp: amount, balance: balance, price: price) {
            return Localized.format("firing.top_up.row.hint.price", MoneyFormatter.string(price))
        }
        let missing = shortfall(topUp: amount, balance: balance, price: price)
        return Localized.format("firing.top_up.row.hint.missing", MoneyFormatter.string(missing))
    }

    /// Which tier the sheet opens pre-selected: the cheapest one that unlocks a
    /// snooze. Falls back to the largest tier when none does (it gets the user
    /// closest), and to the cheapest when there is no usable price.
    static func recommendedAmount(from amounts: [Int], balance: Double, price: Double) -> Int? {
        let sorted = amounts.sorted()
        guard let smallest = sorted.first else { return nil }
        guard usablePrice(price) != nil else { return smallest }
        return sorted.first { isSufficient(topUp: $0, balance: balance, price: price) } ?? sorted.last
    }

    /// Sheet subtitle. Replaces «Минимум — 149 ₽ на следующее откладывание»,
    /// which named the cheapest SKU while claiming it was the amount a snooze
    /// needs — two different numbers whenever the price isn't exactly 149 ₽.
    static func subtitle(amounts: [Int], balance: Double, price: Double) -> String {
        let sorted = amounts.sorted()
        guard let smallest = sorted.first, let largest = sorted.last else { return "" }
        // Each branch is one catalogue entry holding BOTH sentences. Splitting
        // «the snooze costs X» from «Y is enough» would look tidier here and
        // freeze the Russian order — a translator who needs the amount before
        // the price could no longer get it.
        guard let price = usablePrice(price) else {
            return Localized.format(
                "firing.top_up.subtitle.no_price", MoneyFormatter.string(smallest)
            )
        }
        let priceText = MoneyFormatter.string(price)
        guard let enough = recommendedAmount(from: sorted, balance: balance, price: price),
              isSufficient(topUp: enough, balance: balance, price: price) else {
            return Localized.format(
                "firing.top_up.subtitle.insufficient", priceText, MoneyFormatter.string(largest)
            )
        }
        if enough == smallest {
            return Localized.format(
                "firing.top_up.subtitle.smallest", priceText, MoneyFormatter.string(smallest)
            )
        }
        return Localized.format(
            "firing.top_up.subtitle.threshold", priceText, MoneyFormatter.string(enough)
        )
    }
}
