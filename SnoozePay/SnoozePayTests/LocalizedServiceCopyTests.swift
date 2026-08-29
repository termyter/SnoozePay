import XCTest
@testable import SnoozePay

/// Guards the Models/Services/Utilities half of #598 — the keys that reach the
/// user through an alert, an error banner or a notification button.
///
/// The failure these exist for is the one nothing else catches: a mistyped key
/// does not throw, does not log and does not fail to compile. It renders
/// `alarms.error.load_failed` in the alert the user reads when their alarms
/// will not load. `Localized.text` returns the key on a miss precisely so that
/// a test can see it, and this file is what looks.
///
/// The assertions are written against the *enum cases and functions*, not
/// against `Localized.text` directly, so they also cover the wiring: a case
/// that still returns a Swift literal, or one wired to the wrong key, is caught
/// here rather than at a screenshot review.
final class LocalizedServiceCopyTests: XCTestCase {

    /// Every key this issue introduced. Listed once, asserted from two angles
    /// below, so adding a key to the catalogue without adding it here is the
    /// only way to escape both.
    private static let migratedKeys = [
        "alarms.error.load_failed",
        "alarms.error.save_failed",
        "alarms.error.save_blocked",
        "alarms.error.schedule_failed",
        "alarms.error.backend_unavailable",
        "firing.action.dismiss",
        "firing.action.snooze",
        "wallet.error.load_failed",
        "wallet.error.write_failed",
        "wallet.error.write_blocked",
        "referral.error.invalid_format",
        "referral.error.already_applied",
        "referral.error.own_code",
        "referral.error.balance_locked",
        "common.snooze_affordability",
        "deposit.foreign_currency.title",
        "deposit.foreign_currency.message",
        "deposit.foreign_currency.dismiss"
    ]

    // MARK: - The keys exist

    /// The blanket miss detector. `Localized.text` echoes an absent key, so
    /// "resolves to something other than itself" is exactly "the catalogue has
    /// this entry" — and it is the assertion a typo cannot survive.
    func testEveryMigratedKeyResolvesToCopyRatherThanToItself() {
        for key in Self.migratedKeys {
            let copy = Localized.text(key)
            XCTAssertNotEqual(copy, key, "missing catalogue key: \(key)")
            XCTAssertFalse(copy.isEmpty, "empty catalogue value for: \(key)")
        }
    }

    // MARK: - The call sites are wired to them

    func testAlarmRepositoryErrorsReadAsCopy() {
        let underlying = NSError(domain: "test", code: 1)
        let descriptions = [
            AlarmRepository.RepositoryError.decodeFailure(underlying: underlying).errorDescription,
            AlarmRepository.RepositoryError.encodeFailure(underlying: underlying).errorDescription,
            AlarmRepository.RepositoryError.persistBlocked.errorDescription
        ]
        assertAllAreRussianCopy(descriptions)
    }

    func testTransactionRepositoryErrorsReadAsCopy() {
        let underlying = NSError(domain: "test", code: 1)
        let descriptions = [
            TransactionRepository.RepositoryError.decodeFailure(underlying: underlying).errorDescription,
            TransactionRepository.RepositoryError.encodeFailure(underlying: underlying).errorDescription,
            TransactionRepository.RepositoryError.persistBlocked.errorDescription
        ]
        assertAllAreRussianCopy(descriptions)
    }

    func testReferralApplyErrorsReadAsCopy() {
        let descriptions = [
            ReferralService.ApplyError.invalidFormat.errorDescription,
            ReferralService.ApplyError.alreadyApplied.errorDescription,
            ReferralService.ApplyError.cannotApplyOwnCode.errorDescription,
            ReferralService.ApplyError.balanceLocked.errorDescription
        ]
        assertAllAreRussianCopy(descriptions)
        XCTAssertEqual(
            Set(descriptions.compactMap { $0 }).count, descriptions.count,
            "two apply errors resolved to the same string — one of them is wired to the wrong key"
        )
    }

    func testSchedulingErrorReadsAsCopyAndKeepsTheSystemMessage() {
        let backend = AlarmScheduler.SchedulingError.backendUnavailable.errorDescription
        XCTAssertNotEqual(backend, "alarms.error.backend_unavailable")
        XCTAssertTrue(backend?.contains("Настройках") ?? false, String(describing: backend))

        // `.system` is the one substitution in this batch: the OS's own message
        // has to survive into the sentence, not be swallowed by the template.
        let system = AlarmScheduler.SchedulingError.system(message: "limit reached").errorDescription
        XCTAssertNotEqual(system, "alarms.error.schedule_failed")
        XCTAssertTrue(system?.contains("limit reached") ?? false, String(describing: system))
        XCTAssertFalse(system?.contains("%@") ?? true, "the specifier was left unsubstituted")
    }

    // MARK: - The affordability hint's plural variation

    /// The hint moved from a hand-assembled "template + pluralised noun" to a
    /// single catalogue entry with a plural variation, so the form is now
    /// picked by CLDR rather than by `Plural`. These are the boundaries where a
    /// wrong `one`/`few`/`many` mapping in the catalogue would show: 21 takes
    /// the singular in Russian, 11 does not, and 0 takes `many`.
    ///
    /// `SnoozeAffordabilityTests` already pins 0-5 through `hint`; this pins the
    /// teens and twenties that no existing test reaches.
    func testAffordabilityHintPicksRussianFormsAtTheBoundaries() {
        let expected: [(Int, String)] = [
            (0, "Хватит на ~0 откладываний"),
            (1, "Хватит на ~1 откладывание"),
            (2, "Хватит на ~2 откладывания"),
            (5, "Хватит на ~5 откладываний"),
            (11, "Хватит на ~11 откладываний"),
            (14, "Хватит на ~14 откладываний"),
            (21, "Хватит на ~21 откладывание"),
            (22, "Хватит на ~22 откладывания")
        ]
        for (count, text) in expected {
            XCTAssertEqual(
                Localized.format("common.snooze_affordability", count), text,
                "count = \(count)"
            )
        }
    }

    // MARK: - The foreign-currency notice's positional arguments

    /// Six concatenated fragments became one key with `%1$@` and `%2$@`. The
    /// failure mode that swap introduces is silent and inverts the meaning —
    /// the alert would tell the user their wallet holds the storefront's
    /// currency — so the order is asserted rather than mere presence, which is
    /// all `WalletCurrencyTests` can check from the outside.
    func testForeignCurrencyMessagePutsTheWalletCurrencyBeforeTheStorefrontOne() {
        guard let usd = Currency(code: "USD") else {
            return XCTFail("USD is a valid ISO code")
        }
        let text = ForeignCurrencyNotice.message(
            wallet: .rub,
            storefront: usd,
            locale: Locale(identifier: "ru_RU")
        )

        guard let wallet = text.range(of: "RUB"), let storefront = text.range(of: "USD") else {
            return XCTFail("both currencies must be named: \(text)")
        }
        XCTAssertTrue(
            wallet.lowerBound < storefront.lowerBound,
            "the wallet's currency is named first — the arguments are swapped: \(text)"
        )
        XCTAssertFalse(text.contains("$@"), "a positional specifier was left unsubstituted: \(text)")
    }

    // MARK: - Helpers

    /// Copy, not a key: non-nil, non-empty, and containing Cyrillic. The last
    /// part is what distinguishes real Russian from a key that happens to be
    /// present but empty-ish — every key in this batch is lowercase ASCII.
    private func assertAllAreRussianCopy(
        _ descriptions: [String?],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for description in descriptions {
            guard let description, !description.isEmpty else {
                return XCTFail("missing error description", file: file, line: line)
            }
            XCTAssertTrue(
                description.range(of: "\\p{Cyrillic}", options: .regularExpression) != nil,
                "reads as a key rather than as copy: \(description)",
                file: file,
                line: line
            )
        }
    }
}
