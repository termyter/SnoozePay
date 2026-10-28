import UIKit
import XCTest
@testable import SnoozePay

/// Pins the copy that this slice of #600 moved out of
/// `SettingsViewController+Sections.swift` into `Localizable.xcstrings`.
///
/// A wrong key is silent: `Localized.text` hands the key back, the row renders
/// `settings.row.volume` where «Громкость» used to be, and the build ships. So,
/// mirroring `AlarmEditorCopyTests`, the assertions come in three layers and a
/// red run names which one broke:
///
///  1. **Catalogue layer** — every key exists.
///  2. **Copy layer** — every key still holds the exact words it held before
///     the migration, transcribed here from the pre-migration literals rather
///     than read back out of the file under test.
///  3. **Call-site layer** — the real rows are built through the data source
///     and what they render is compared against the catalogue. Layers 1 and 2
///     are blind to a typo in the *key* at the call site, because in that case
///     the catalogue itself is fine.
///
/// # What layer 3 does NOT reach
///
/// Five of the sixteen keys are only ever read while a `UIAlertController` is
/// being assembled, and this slice left that assembly inline in
/// `presentRecoveryConfirmation()` / the two pickers. They are covered by
/// layers 1 and 2 only:
///
///  * `settings.picker.applies_to_new_alarms`
///  * `settings.recovery.alert_title`
///  * `settings.recovery.alert_message`
///  * `settings.recovery.confirm`
///  * `common.button.cancel` — its words are asserted here, but no call site
///    of it is; the key predates this slice and three other screens read it.
///
/// "Not covered in this slice", not "not reachable": the same move that made
/// the recovery row testable would work here — extracting
/// `makeRecoveryAlert() -> UIAlertController` would put `alert.title`,
/// `alert.message` and `alert.actions.map(\.title)` in reach with no window
/// and no presentation at all. That is a change to production structure, and
/// this slice moves strings only.
@MainActor
final class SettingsRowCopyTests: XCTestCase {

    /// Explicitly owns a known-empty native inventory; no generic backend defaults to success.
    private typealias NoopScheduler = KnownEmptyRecoveryScheduler

    // MARK: - Layer 1 + 2: the catalogue and its words

    /// The strings as they read on screen today, copied from the literals this
    /// slice replaced. A list derived from the catalogue would agree with any
    /// mistake in it.
    private static let copy: [String: String] = [
        "common.button.cancel": "Отмена",
        "settings.picker.applies_to_new_alarms": "Применяется к новым будильникам",
        "settings.picker.minutes_option": "%lld мин",
        "settings.recovery.alert_message": "Будут удалены только данные, которые не удалось загрузить: "
            + "будильники, история операций или и то и другое. Корректный сохранённый баланс останется прежним. "
            + "При некорректном балансе история не удалится. Это действие нельзя отменить.",
        "settings.recovery.balance_invalid": "История операций не удалена: не удалось подтвердить сохранённый баланс. "
            + "Данные остаются заблокированными.",
        "settings.recovery.alert_title": "Стереть повреждённые данные?",
        "settings.recovery.confirm": "Подтвердить",
        "settings.recovery.row_subtitle": "Хранилище повреждено и заблокировано",
        "settings.recovery.row_title": "Стереть повреждённые данные",
        "settings.row.contact": "Связаться с нами",
        "settings.row.default_price": "Цена откладывания по умолчанию",
        "settings.row.privacy_policy": "Политика конфиденциальности",
        "settings.row.progressive_price": "Прогрессивная цена",
        "settings.row.snooze_duration": "Длительность откладывания",
        "settings.row.terms": "Пользовательское соглашение",
        "settings.row.vibration": "Вибрация",
        "settings.row.volume": "Громкость"
    ]

    func testEveryKeyResolvesToCopyRatherThanToItself() {
        for key in Self.copy.keys {
            XCTAssertNotEqual(Localized.text(key), key, "missing catalogue key: \(key)")
        }
    }

    func testCatalogueStillHoldsTheWordsTheScreenShipped() {
        for (key, expected) in Self.copy {
            XCTAssertEqual(Localized.text(key), expected, "copy drifted for: \(key)")
        }
    }

    func testRecoveryConfirmationExplainsBalancePreservationAndRefusal() {
        let message = Localized.text("settings.recovery.alert_message")
        XCTAssertTrue(message.contains("Корректный сохранённый баланс останется прежним."))
        XCTAssertTrue(message.contains("При некорректном балансе история не удалится."))
    }

    func testRecoveryOnlyClearsTheFailedStoreAndPreservesTheWallet() throws {
        for transactionFailed in [true, false] {
            let suite = "test.settings.recovery.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let ledger = TransactionRepository(defaults: defaults)
            let alarms = AlarmRepository(defaults: defaults, scheduler: NoopScheduler())
            let wallet = BalanceService(defaults: defaults, transactionRepository: ledger,
                                        notificationCenter: NotificationCenter())
            XCTAssertTrue(wallet.topUp(amount: 149))
            alarms.save(Alarm(name: "Healthy", penaltyAmount: 50))
            let failedKey = transactionFailed ? "stored_transactions" : "stored_alarms"
            let healthyKey = transactionFailed ? "stored_alarms" : "stored_transactions"
            let healthyBytes = defaults.data(forKey: healthyKey)
            defaults.set(Data("corrupt".utf8), forKey: failedKey)
            if transactionFailed {
                XCTAssertThrowsError(try ledger.fetchAllChecked())
            } else {
                XCTAssertThrowsError(try alarms.fetchAllChecked())
            }
            let sut = SettingsViewController(alarmDefaults: AlarmDefaults(defaults: defaults))
            sut.loadViewIfNeeded()

            sut.performRecovery(balanceService: wallet, alarmRepository: alarms)

            XCTAssertNil(defaults.object(forKey: failedKey))
            XCTAssertEqual(defaults.data(forKey: healthyKey), healthyBytes)
            XCTAssertEqual(wallet.balance, 149)
            XCTAssertFalse(ledger.lastLoadFailed)
            XCTAssertFalse(alarms.lastLoadFailed)
        }
    }

    @available(iOS 26.0, *)
    func testRecoverySettingsRouteRequiresNativeCleanupAndPreservesWalletOnFailure() throws {
        for cleanupFails in [false, true] {
            let suite = "test.settings.nativeRecovery.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let ledger = TransactionRepository(defaults: defaults)
            let wallet = BalanceService(defaults: defaults, transactionRepository: ledger,
                                        notificationCenter: NotificationCenter())
            XCTAssertTrue(wallet.topUp(amount: 149))
            let id = UUID()
            var inventory: Set<UUID> = [id]
            let native = AlarmKitScheduler(cancelAlarm: {
                if cleanupFails { throw NSError(domain: "CancelFixture", code: 1) }
                inventory.remove($0)
            }, readRegisteredAlarmIDs: { inventory })
            let scheduler = AlarmScheduler(notificationCenter: InertNotificationCenter(), alarmKit: native)
            let alarms = AlarmRepository(defaults: defaults, scheduler: scheduler)
            let corrupt = Data("corrupt".utf8)
            defaults.set(corrupt, forKey: "stored_alarms")
            defaults.set(corrupt, forKey: "stored_transactions")
            XCTAssertThrowsError(try alarms.fetchAllChecked())
            XCTAssertThrowsError(try ledger.fetchAllChecked())
            let sut = RecoverySettingsSpy(alarmDefaults: AlarmDefaults(defaults: defaults))
            sut.loadViewIfNeeded()
            sut.performRecovery(balanceService: wallet, alarmRepository: alarms)
            XCTAssertEqual(wallet.balance, 149)
            XCTAssertNil(defaults.object(forKey: "stored_transactions"), "wallet recovery still runs first")
            XCTAssertFalse(ledger.lastLoadFailed)
            XCTAssertEqual(defaults.data(forKey: AlarmRepository.corruptBackupKey), corrupt)
            if cleanupFails {
                XCTAssertEqual(inventory, [id])
                XCTAssertEqual(defaults.data(forKey: "stored_alarms"), corrupt)
                XCTAssertTrue(alarms.lastLoadFailed)
                XCTAssertEqual(sut.alert?.title, Localized.text("settings.recovery.alarms_failed_title"))
                XCTAssertEqual(sut.alert?.message, Localized.text("settings.recovery.alarms_cleanup_failed"))
            } else {
                XCTAssertTrue(inventory.isEmpty)
                XCTAssertNil(defaults.object(forKey: "stored_alarms"))
                XCTAssertFalse(alarms.lastLoadFailed)
                XCTAssertNil(sut.alert)
            }
        }
    }

    func testBusyRecoveryShowsRetryCopyAndKeepsAlarmBytesLocked() throws {
        let suite = "test.settings.busyRecovery.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let ledger = TransactionRepository(defaults: defaults)
        let wallet = BalanceService(defaults: defaults, transactionRepository: ledger,
                                    notificationCenter: NotificationCenter())
        let alarms = AlarmRepository(defaults: defaults, scheduler: NoopScheduler(recoveryError: .busy))
        let corrupt = Data("corrupt".utf8)
        defaults.set(corrupt, forKey: "stored_alarms")
        let sut = RecoverySettingsSpy(alarmDefaults: AlarmDefaults(defaults: defaults))
        sut.loadViewIfNeeded()
        sut.performRecovery(balanceService: wallet, alarmRepository: alarms)
        XCTAssertEqual(sut.alert?.message, Localized.text("settings.recovery.alarms_busy"))
        XCTAssertEqual(defaults.data(forKey: "stored_alarms"), corrupt)
        XCTAssertTrue(alarms.lastLoadFailed)
        XCTAssertNotEqual(Localized.text("settings.recovery.alarms_busy"), "settings.recovery.alarms_busy")
    }

    private final class RecoverySettingsSpy: SettingsViewController {
        var alert: UIAlertController?
        override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool,
                              completion: (() -> Void)? = nil) {
            alert = viewControllerToPresent as? UIAlertController
            completion?()
        }
    }

    /// `%lld` and not `%@`: the call sites pass an `Int`, and a mismatched
    /// specifier prints garbage rather than failing to build.
    func testMinutesOptionSubstitutesTheNumber() {
        XCTAssertEqual(Localized.format("settings.picker.minutes_option", 7), "7 мин")
    }

    // MARK: - Layer 3: the rows are wired to those keys

    func testFinanceRowsRenderCatalogueCopy() {
        let sut = makeSUT(snoozeMinutes: 7)
        let section = sut.sectionIndex(of: .finance)

        assertRenders(["settings.row.default_price"], in: sut, at: IndexPath(row: 0, section: section))
        assertRenders(["settings.row.snooze_duration"], in: sut, at: IndexPath(row: 1, section: section))
        XCTAssertTrue(
            Self.strings(in: sut.cell(at: IndexPath(row: 1, section: section))).contains("7 мин"),
            "the snooze-duration row lost its «N мин» trailing value"
        )
    }

    func testSoundRowsRenderCatalogueCopy() {
        let sut = makeSUT()
        let section = sut.sectionIndex(of: .soundNotifications)

        assertRenders(["settings.row.volume"], in: sut, at: IndexPath(row: 0, section: section))
        assertRenders(["settings.row.vibration"], in: sut, at: IndexPath(row: 1, section: section))
    }

    func testRulesRowRendersCatalogueCopy() {
        let sut = makeSUT()
        assertRenders(
            ["settings.row.progressive_price"],
            in: sut,
            at: IndexPath(row: 0, section: sut.sectionIndex(of: .rules))
        )
    }

    func testOtherRowsRenderCatalogueCopy() {
        let sut = makeSUT()
        let section = sut.sectionIndex(of: .other)

        assertRenders(["settings.row.privacy_policy"], in: sut, at: IndexPath(row: 0, section: section))
        assertRenders(["settings.row.terms"], in: sut, at: IndexPath(row: 1, section: section))
        assertRenders(["settings.row.contact"], in: sut, at: IndexPath(row: 2, section: section))
    }

    /// The recovery row is built directly rather than through the data source:
    /// it only exists while a repository reports `lastLoadFailed`, which is
    /// global state this test has no honest way to fake. The index path is a
    /// live one so the dequeue is real; the builder ignores everything about it
    /// beyond that.
    func testRecoveryRowRendersCatalogueCopy() {
        let sut = makeSUT()
        let cell = sut.makeRecoveryCell(at: IndexPath(row: 0, section: sut.sectionIndex(of: .finance)))
        let rendered = Self.strings(in: cell)

        for key in ["settings.recovery.row_title", "settings.recovery.row_subtitle"] {
            XCTAssertTrue(rendered.contains(Localized.text(key)), "recovery row is not wired to \(key)")
        }
    }

    // MARK: - Helpers

    private func makeSUT(snoozeMinutes: Int? = nil) -> SettingsViewController {
        let suite = "test.settings.rowcopy.\(UUID().uuidString)"
        let defaults = AlarmDefaults(defaults: UserDefaults(suiteName: suite)!)
        if let snoozeMinutes { defaults.snoozeMinutes = snoozeMinutes }
        let sut = SettingsViewController(alarmDefaults: defaults)
        sut.loadViewIfNeeded()
        return sut
    }

    private func assertRenders(
        _ keys: [String],
        in sut: SettingsViewController,
        at indexPath: IndexPath,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let rendered = Self.strings(in: sut.cell(at: indexPath))
        for key in keys {
            XCTAssertTrue(
                rendered.contains(Localized.text(key)),
                "row \(indexPath) renders \(rendered) — not the copy of \(key)",
                file: file,
                line: line
            )
        }
    }

    private static func strings(in view: UIView) -> [String] {
        var found: [String] = []
        if let label = view as? UILabel {
            found.append(contentsOf: [label.text, label.attributedText?.string].compactMap { $0 })
        }
        if let control = view as? UIControl {
            found.append(contentsOf: [control.accessibilityLabel].compactMap { $0 })
        }
        return found + view.subviews.flatMap { strings(in: $0) }
    }
}

private extension SettingsViewController {

    /// Section indices are POSITIONS in the live table, not raw values:
    /// `.referral` is hidden behind a flag (#676), so everything after it
    /// shifts up and a raw-value probe reads the wrong section in silence.
    func sectionIndex(of section: Section, file: StaticString = #filePath, line: UInt = #line) -> Int {
        guard let index = visibleSections.firstIndex(of: section) else {
            XCTFail("section \(section) is not visible; nothing to probe", file: file, line: line)
            return 0
        }
        return index
    }

    func cell(at indexPath: IndexPath) -> UITableViewCell {
        self.tableView(self.tableView, cellForRowAt: indexPath)
    }
}
