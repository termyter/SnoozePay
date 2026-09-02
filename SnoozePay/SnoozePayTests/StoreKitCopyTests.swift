import StoreKit
import UserNotifications
import XCTest
@testable import SnoozePay

/// Pins the copy that this slice of #598 moved out of `StoreKitService` and
/// `StoreKitRestore` and into `Localizable.xcstrings`.
///
/// These are the strings a user meets when their money is already gone: a
/// purchase that would not credit, a receipt that would not verify, a restore
/// that failed. `Localized.text` hands back the key on a miss, so a mistyped
/// key ships as `deposit.error.credit_failed` inside a purchase-failure alert
/// and the build stays green — nothing else in the suite would notice.
///
/// Three layers, so a red run names which one broke:
///
///  1. **Catalogue layer** — every key exists and does not resolve to itself.
///  2. **Copy layer** — every key still holds the exact words it held before
///     the migration, transcribed from the pre-migration literals rather than
///     read back out of the file under test. A list derived from the catalogue
///     would agree with any mistake in it.
///  3. **Call-site layer** — the production entry points are invoked and what
///     they return is compared against the catalogue. Layers 1 and 2 are both
///     blind to a typo in the *key* at the call site, because there the
///     catalogue itself is fine.
@MainActor
final class StoreKitCopyTests: XCTestCase {

    // MARK: - Layers 1 + 2: the catalogue and its words

    private static let copy: [String: String] = [
        "deposit.error.credit_failed": "Не удалось зачислить покупку. Свяжитесь с поддержкой.",
        "deposit.error.dedup_degraded":
            "Не удалось обработать покупку. Перезапустите приложение или свяжитесь с поддержкой.",
        "deposit.error.foreign_currency":
            "Покупка оплачена в другой валюте, чем баланс кошелька, и зачислить её не получилось. "
            + "Свяжитесь с поддержкой.",
        "deposit.error.products_load_failed":
            "Не удалось загрузить пакеты пополнения. Проверь интернет-соединение.",
        "deposit.error.unknown_product": "Неизвестный пакет пополнения. Обнови приложение.",
        "deposit.error.unknown_result": "Покупка не выполнена. Обнови приложение и попробуй ещё раз.",
        "deposit.error.verification_failed":
            "Не удалось проверить чек покупки. Если деньги списаны — напиши в поддержку.",
        "deposit.notification.credited.title": "Баланс пополнен",
        "deposit.notification.credited.body": "Баланс пополнен на %lld ₽.",
        "deposit.notification.failed.title": "Покупка пополнения",
        "deposit.restore.success.title": "Запрос отправлен",
        "deposit.restore.success.message":
            "Если у вас есть предыдущие покупки, баланс обновится автоматически в течение "
            + "нескольких секунд.",
        "deposit.restore.error.title": "Не удалось восстановить покупки",
        "deposit.restore.error.network": "Проверьте подключение к интернету и попробуйте снова.",
        "deposit.restore.error.generic": "%@\n\nЕсли проблема повторяется, свяжитесь с поддержкой.",
        "deposit.restore.error.cancelled": "Действие отменено.",
        "deposit.restore.error.storefront": "Покупки временно недоступны в вашем регионе.",
        "deposit.restore.error.not_entitled": "Войдите в Apple ID в Настройках и попробуйте снова.",
        "deposit.restore.error.payment_not_allowed":
            "В вашем Apple ID запрещены покупки. Проверьте настройки экранного времени.",
        "deposit.restore.error.icloud": "Проверьте подключение к интернету и доступ к iCloud в Настройках."
    ]

    func testEveryMigratedKeyResolvesToCopy() {
        for key in Self.copy.keys.sorted() {
            XCTAssertNotNil(Localized.optionalText(key), "missing catalogue key: \(key)")
            XCTAssertNotEqual(
                Localized.text(key), key,
                "\(key) resolves to itself — the entry is absent or holds the key as its value"
            )
        }
    }

    func testMigratedCopyStillReadsTheWayItDidBefore() {
        for (key, expected) in Self.copy {
            XCTAssertEqual(Localized.text(key), expected, "copy drifted for \(key)")
        }
    }

    /// Two of these keys are one word apart from an entry that already existed
    /// before the slice, and collapsing them would silently rewrite copy on a
    /// screen this issue does not touch. `deposit.error.products_unavailable`
    /// is what the deposit sheet shows when the catalogue comes back empty;
    /// `deposit.error.products_load_failed` is what the *load* posts when it
    /// throws. Different words, different moment — asserted apart so a later
    /// tidy-up cannot merge them without a red run.
    func testTheLoadFailureIsNotTheEmptyCatalogueCopy() {
        XCTAssertNotEqual(
            Localized.text("deposit.error.products_load_failed"),
            Localized.text("deposit.error.products_unavailable")
        )
        XCTAssertNotEqual(
            Localized.text("deposit.error.unknown_result"),
            Localized.text("common.purchase_failed.title")
        )
    }

    // MARK: - Layer 3: StoreKitService's published constants

    /// The three failure messages are read by the deposit sheet, the firing
    /// top-up sheet and the no-balance state, which is why they are surfaced as
    /// type members rather than inlined. Each has to keep reading as copy — a
    /// member wired to the wrong key still compiles and still returns a
    /// `String`.
    func testServiceFailureMessagesReadAsCopyRatherThanAsKeys() {
        let messages = [
            StoreKitService.ledgerLockedFailureMessage,
            StoreKitService.degradedDedupFailureMessage,
            StoreKitService.foreignCurrencyFailureMessage
        ]
        for message in messages {
            assertIsRussianCopy(message)
        }
        XCTAssertEqual(
            Set(messages).count, messages.count,
            "two failure messages resolved to the same string — one is wired to the wrong key"
        )
        XCTAssertEqual(StoreKitService.ledgerLockedFailureMessage, Localized.text("deposit.error.credit_failed"))
        XCTAssertEqual(StoreKitService.degradedDedupFailureMessage, Localized.text("deposit.error.dedup_degraded"))
        XCTAssertEqual(
            StoreKitService.foreignCurrencyFailureMessage,
            Localized.text("deposit.error.foreign_currency")
        )
    }

    // MARK: - Layer 3: the deferred-purchase local notifications

    /// The credited notification is the one entry in this batch that takes an
    /// argument, so the number has to survive into the sentence rather than be
    /// swallowed by the template.
    func testCreditedNotificationSubstitutesTheAmount() {
        let poster = LocalNotificationPosterSpy()
        let (defaults, name) = makeSuite()
        defer { defaults.removePersistentDomain(forName: name) }
        let service = StoreKitService(notificationPoster: poster, defaults: defaults, startListener: false)

        service.postPurchaseCompleted(299)

        let content = poster.requests.first?.content
        XCTAssertEqual(content?.title, Localized.text("deposit.notification.credited.title"))
        XCTAssertEqual(content?.body, "Баланс пополнен на 299 ₽.")
        XCTAssertFalse(content?.body.contains("%") ?? true, "the specifier was left unsubstituted")
    }

    /// The failure notification carries the failure's own message as its body,
    /// so only the title comes from the catalogue — and that is exactly the
    /// half a key typo would replace with `deposit.notification.failed.title`.
    func testFailedNotificationTitleComesFromTheCatalogue() {
        let poster = LocalNotificationPosterSpy()
        let (defaults, name) = makeSuite()
        defer { defaults.removePersistentDomain(forName: name) }
        let service = StoreKitService(notificationPoster: poster, defaults: defaults, startListener: false)

        service.postPurchaseFailed(StoreKitService.ledgerLockedFailureMessage)

        let content = poster.requests.first?.content
        XCTAssertEqual(content?.title, Localized.text("deposit.notification.failed.title"))
        XCTAssertEqual(content?.body, Localized.text("deposit.error.credit_failed"))
    }

    // MARK: - Layer 3: the restore error mapping

    /// Every typed branch of `StoreKitRestoreErrorCopy` against the key it is
    /// supposed to read. `StoreKitRestoreErrorCopyTests` already pins the
    /// words; this pins the wiring, which is the half that survives a rename
    /// of the entry.
    func testRestoreErrorBranchesReadTheirCatalogueEntries() {
        let expectations: [(Error, String)] = [
            (StoreKitError.userCancelled, "deposit.restore.error.cancelled"),
            (StoreKitError.networkError(URLError(.timedOut)), "deposit.restore.error.network"),
            (StoreKitError.notAvailableInStorefront, "deposit.restore.error.storefront"),
            (StoreKitError.notEntitled, "deposit.restore.error.not_entitled"),
            (
                NSError(domain: SKErrorDomain, code: SKError.Code.paymentNotAllowed.rawValue),
                "deposit.restore.error.payment_not_allowed"
            ),
            (
                NSError(domain: SKErrorDomain, code: SKError.Code.cloudServiceRevoked.rawValue),
                "deposit.restore.error.icloud"
            ),
            (URLError(.notConnectedToInternet), "deposit.restore.error.network")
        ]
        for (error, key) in expectations {
            XCTAssertEqual(
                StoreKitRestoreErrorCopy.message(for: error), Localized.text(key),
                "the branch for \(error) is not reading \(key)"
            )
        }
    }

    /// The untyped fallback leads with the system's own description, so it is a
    /// substitution and not a concatenation: the suffix may have to precede the
    /// description in another language.
    func testUnknownRestoreErrorKeepsTheSystemDescriptionInTheSentence() {
        let error = NSError(
            domain: "com.snoozepay.test",
            code: 42,
            userInfo: [NSLocalizedDescriptionKey: "Boom"]
        )
        let message = StoreKitRestoreErrorCopy.message(for: error)

        XCTAssertTrue(message.hasPrefix("Boom"), message)
        XCTAssertTrue(message.contains("свяжитесь с поддержкой"), message)
        XCTAssertFalse(message.contains("%@"), "the specifier was left unsubstituted: \(message)")
    }

    // MARK: - Helpers

    /// An isolated defaults suite, so the service under test never reads
    /// `.standard` — and never `.shared`, which spawns the
    /// `Transaction.updates` listener.
    private func makeSuite() -> (UserDefaults, String) {
        let name = "test_storekit_copy_\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    /// Copy, not a key: non-empty and containing Cyrillic. Every key in this
    /// batch is lowercase ASCII, so the second half is what tells a resolved
    /// entry from an echoed key.
    private func assertIsRussianCopy(
        _ text: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(text.isEmpty, "empty copy", file: file, line: line)
        XCTAssertTrue(
            text.range(of: "\\p{Cyrillic}", options: .regularExpression) != nil,
            "reads as a key rather than as copy: \(text)",
            file: file,
            line: line
        )
    }
}
