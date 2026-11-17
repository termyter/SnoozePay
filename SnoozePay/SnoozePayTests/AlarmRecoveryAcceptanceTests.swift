import UIKit
import XCTest
@testable import SnoozePay

@available(iOS 26.0, *)
@MainActor
final class AlarmRecoveryAcceptanceTests: XCTestCase {
    private static let cleanupFailedRussian = "Не удалось подтвердить отмену всех системных будильников. "
        + "Часть системных будильников уже могла быть отменена. "
        + "Повреждённые данные будильников не удалены и остаются заблокированными. "
        + "Восстановление истории операций могло уже завершиться."
    private static let cleanupFailedEnglish = "Could not confirm that all system alarms were cancelled. "
        + "Some system alarms may already have been cancelled. "
        + "Damaged alarm data was not erased and remains locked. "
        + "Transaction history recovery may already have completed."

    func testCompiledCleanupFailureCopyExplainsPartialCancellationInBothLanguages() throws {
        let expected = ["ru": Self.cleanupFailedRussian, "en": Self.cleanupFailedEnglish]
        for (language, literal) in expected {
            let url = try XCTUnwrap(Bundle.main.url(
                forResource: "Localizable", withExtension: "strings", subdirectory: "\(language).lproj"
            ))
            let plist = try PropertyListSerialization.propertyList(
                from: Data(contentsOf: url), options: [], format: nil
            )
            let table = try XCTUnwrap(plist as? [String: String])
            XCTAssertEqual(table["settings.recovery.alarms_cleanup_failed"], literal)
        }
    }

    func testSettingsNativeRecoveryPreservesEveryHealthyWalletFieldOnSuccessAndFailure() throws {
        for cleanupFails in [false, true] {
            let suite = "test.settings.healthyWalletRecovery.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let ledger = TransactionRepository(defaults: defaults, wakeStore: WakeEventStore(defaults: defaults))
            let wallet = BalanceService(defaults: defaults, transactionRepository: ledger,
                                        notificationCenter: NotificationCenter())
            let purchases = StoreKitService(notificationPoster: LocalNotificationPosterSpy(), defaults: defaults)
            let usd = try XCTUnwrap(Currency(code: "USD"))
            XCTAssertEqual(wallet.topUpFromPurchase(amount: 300, currency: usd), .credited)
            XCTAssertTrue(wallet.charge(amount: 50, alarmID: nil))
            XCTAssertEqual(purchases.markProcessed(transactionID: 42), .recorded)
            XCTAssertEqual(purchases.markProcessed(transactionID: 99), .recorded)
            XCTAssertEqual(try ledger.fetchAllChecked().count, 2)
            let before = try snapshotWallet(defaults)
            XCTAssertEqual(before.cache.doubleValue, 250)
            XCTAssertEqual(before.currency, "USD")
            XCTAssertEqual(before.processedIDs, ["42", "99"])

            let id = UUID()
            var inventory: Set<UUID> = [id]
            let native = AlarmKitScheduler(cancelAlarm: {
                if cleanupFails { throw NSError(domain: "HealthyWalletCancelFixture", code: 1) }
                inventory.remove($0)
            }, readRegisteredAlarmIDs: { inventory })
            let scheduler = AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: native)
            let alarms = AlarmRepository(defaults: defaults, scheduler: scheduler)
            let corrupt = Data("damaged alarms beside a healthy wallet".utf8)
            defaults.set(corrupt, forKey: "stored_alarms")
            XCTAssertThrowsError(try alarms.fetchAllChecked())
            let settings = RecoverySettingsSpy(alarmDefaults: AlarmDefaults(defaults: defaults))
            settings.loadViewIfNeeded()

            settings.performRecovery(balanceService: wallet, alarmRepository: alarms)

            XCTAssertEqual(try snapshotWallet(defaults), before,
                           "alarm recovery must preserve exact ledger/cache/currency/opening/processed-ID values")
            XCTAssertEqual(wallet.balance, 250)
            XCTAssertFalse(ledger.lastLoadFailed)
            if cleanupFails {
                XCTAssertEqual(settings.alert?.message, Self.cleanupFailedRussian)
                XCTAssertEqual(inventory, [id])
                XCTAssertEqual(defaults.data(forKey: "stored_alarms"), corrupt)
                XCTAssertTrue(alarms.lastLoadFailed)
            } else {
                XCTAssertNil(settings.alert)
                XCTAssertTrue(inventory.isEmpty)
                XCTAssertNil(defaults.object(forKey: "stored_alarms"))
                XCTAssertFalse(alarms.lastLoadFailed)
            }
            XCTAssertEqual(defaults.data(forKey: AlarmRepository.corruptBackupKey), corrupt)
        }
    }

    func testPartialNativeCleanupRetryCancelsOnlyRemainingIDBeforeCommitting() throws {
        let suite = "test.native.partialRecoveryRetry.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let remaining = UUID(uuidString: "53000000-0000-0000-0000-000000000001")!
        let corrupt = Data("damaged alarm IDs cannot be trusted".utf8)
        defaults.set(corrupt, forKey: "stored_alarms")
        var inventory: Set<UUID> = [original, remaining]
        var cancelled: [UUID] = []
        var reads = 0
        var allowRemainingCancellation = false
        let native = AlarmKitScheduler(cancelAlarm: { id in
            XCTAssertEqual(defaults.data(forKey: "stored_alarms"), corrupt)
            cancelled.append(id)
            if id == original || allowRemainingCancellation { inventory.remove(id) }
        }, readRegisteredAlarmIDs: {
            reads += 1
            XCTAssertEqual(defaults.data(forKey: "stored_alarms"), corrupt,
                           "even an empty readback must precede the destructive commit")
            return inventory
        })
        let scheduler = AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: native)
        let alarms = AlarmRepository(defaults: defaults, scheduler: scheduler)

        XCTAssertThrowsError(try alarms.clearCorruptState().get()) {
            XCTAssertEqual($0 as? AlarmRecoveryError, .registrationsRemain)
        }
        XCTAssertEqual(Set(cancelled), [original, remaining])
        XCTAssertEqual(cancelled.count, 2)
        XCTAssertEqual(reads, 2)
        XCTAssertEqual(inventory, [remaining])
        XCTAssertEqual(defaults.data(forKey: "stored_alarms"), corrupt)
        XCTAssertEqual(defaults.data(forKey: AlarmRepository.corruptBackupKey), corrupt)
        XCTAssertTrue(alarms.lastLoadFailed)
        XCTAssertFalse(alarms.save(Alarm(enabled: false)))

        allowRemainingCancellation = true
        try alarms.clearCorruptState().get()

        XCTAssertEqual(Array(cancelled.dropFirst(2)), [remaining], "retry must use the fresh inventory")
        XCTAssertEqual(reads, 4)
        XCTAssertTrue(inventory.isEmpty)
        XCTAssertNil(defaults.object(forKey: "stored_alarms"))
        XCTAssertEqual(defaults.data(forKey: AlarmRepository.corruptBackupKey), corrupt)
        XCTAssertFalse(alarms.lastLoadFailed)
    }

    private struct WalletSnapshot: Equatable {
        let ledger: Data
        let cache: NSNumber
        let currency: String
        let opening: NSNumber
        let processedIDs: [String]
    }

    private func snapshotWallet(_ defaults: UserDefaults) throws -> WalletSnapshot {
        WalletSnapshot(
            ledger: try XCTUnwrap(defaults.data(forKey: "stored_transactions")),
            cache: try XCTUnwrap(defaults.object(forKey: "user_balance") as? NSNumber),
            currency: try XCTUnwrap(defaults.string(forKey: WalletCurrencyStore.storageKey)),
            opening: try XCTUnwrap(defaults.object(forKey: LocalBalanceLedgerStore.openingBalanceKey) as? NSNumber),
            processedIDs: try XCTUnwrap(defaults.stringArray(forKey: "storekit.processed_tx_ids"))
        )
    }

    private final class RecoverySettingsSpy: SettingsViewController {
        var alert: UIAlertController?
        override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool,
                              completion: (() -> Void)? = nil) {
            alert = viewControllerToPresent as? UIAlertController
            completion?()
        }
    }
}
