import XCTest

/// Pins `makeIsolatedDefaults` (#1118): every test starts on an empty suite,
/// a returned slot is handed out again under the same name — the whole fd fix
/// rests on that — and hand-rolled suites only disappear, file by file.
final class IsolatedDefaultsTestSupportTests: XCTestCase {

    func testSlotLeftDirtyIsEmptiedWhenHandedOut() {
        // The pool hands out the lowest free slot, so this is the one we get next.
        let peek = IsolatedDefaultsPool.checkOut()
        IsolatedDefaultsPool.checkIn(peek.slot)
        let stale = reopenIsolatedDefaults(named: IsolatedDefaultsPool.suiteName(peek.slot))
        stale.set(1, forKey: "stale")
        XCTAssertNotNil(stale.object(forKey: "stale"), "pollution did not land — the check below would be vacuous")

        let (defaults, name) = makeIsolatedSuite()

        XCTAssertEqual(name, IsolatedDefaultsPool.suiteName(peek.slot))
        XCTAssertNil(defaults.object(forKey: "stale"))
    }

    func testReturnedSlotIsHandedOutAgainUnderTheSameNameAndEmpty() {
        let first = IsolatedDefaultsPool.checkOut()
        first.defaults.set(1, forKey: "probe")
        XCTAssertNotNil(first.defaults.object(forKey: "probe"))
        IsolatedDefaultsPool.checkIn(first.slot)

        let second = IsolatedDefaultsPool.checkOut()
        defer { IsolatedDefaultsPool.checkIn(second.slot) }

        let name = IsolatedDefaultsPool.suiteName(second.slot)
        XCTAssertEqual(name, IsolatedDefaultsPool.suiteName(first.slot), "a new name per hand-out is the #1118 leak")
        XCTAssertTrue((second.defaults.persistentDomain(forName: name) ?? [:]).isEmpty)
        XCTAssertNil(second.defaults.object(forKey: "probe"))
    }

    /// Teardown blocks run last-registered-first, so the check registered
    /// before the helper runs after the helper's own cleanup.
    func testSuiteIsEmptiedAndReturnedAfterTheTestEnds() {
        let slotsBefore = IsolatedDefaultsPool.slotsInUse
        let created = NSMutableArray()
        addTeardownBlock {
            XCTAssertEqual(created.count, 1, "the suite was never created — nothing to check")
            for case let name as String in created {
                let domain = self.reopenIsolatedDefaults(named: name).persistentDomain(forName: name) ?? [:]
                XCTAssertTrue(domain.isEmpty, "\(name) still holds \(domain.keys.sorted()) after teardown")
            }
            XCTAssertEqual(IsolatedDefaultsPool.slotsInUse, slotsBefore, "the slot was not returned")
        }
        let (defaults, name) = makeIsolatedSuite()
        created.add(name)
        defaults.set("value", forKey: "probe")
        XCTAssertEqual(IsolatedDefaultsPool.slotsInUse, slotsBefore + 1)
        XCTAssertEqual(defaults.persistentDomain(forName: name)?["probe"] as? String, "value")
    }

    func testReopenedInstanceSeesTheWrite() {
        let (defaults, name) = makeIsolatedSuite()
        defaults.set(42, forKey: "probe")
        XCTAssertEqual(reopenIsolatedDefaults(named: name).integer(forKey: "probe"), 42)
    }

    func testTwoSuitesInOneTestAreSeparate() {
        let first = makeIsolatedSuite()
        let second = makeIsolatedSuite()
        first.defaults.set(1, forKey: "probe")

        XCTAssertNotEqual(first.name, second.name)
        XCTAssertNil(second.defaults.object(forKey: "probe"))
    }

    /// A slot nobody holds is not wiped or "freed" by a stray check-in.
    func testCheckInOfASlotNotHandedOutLeavesItAlone() {
        let peek = IsolatedDefaultsPool.checkOut()
        IsolatedDefaultsPool.checkIn(peek.slot)
        let name = IsolatedDefaultsPool.suiteName(peek.slot)
        let outside = reopenIsolatedDefaults(named: name)
        defer { outside.removePersistentDomain(forName: name) }
        outside.set(1, forKey: "probe")
        let slotsBefore = IsolatedDefaultsPool.slotsInUse

        IsolatedDefaultsPool.checkIn(peek.slot)

        XCTAssertEqual(outside.integer(forKey: "probe"), 1, "a check-in of a free slot wiped it")
        XCTAssertEqual(IsolatedDefaultsPool.slotsInUse, slotsBefore)
    }

    func testOnlyPoolSuitesCountAsPoolNames() {
        XCTAssertTrue(IsolatedDefaultsPool.isPoolName(IsolatedDefaultsPool.suiteName(0)))
        XCTAssertTrue(IsolatedDefaultsPool.isPoolName(IsolatedDefaultsPool.suiteName(12)))
        for name in [
            "BalanceServiceTests-\(UUID().uuidString)", "SnoozePayTests.isolated.", "SnoozePayTests.isolated.x",
            "SnoozePayTests.isolated.-1", "SnoozePayTests.isolated.01", "xSnoozePayTests.isolated.0"
        ] {
            XCTAssertFalse(IsolatedDefaultsPool.isPoolName(name), name)
        }
    }

    func testRatchetCountsBothSpellingsAndSkipsComments() {
        let plain = "UserDefaults(" + "suiteName: a)"
        let viaInit = "UserDefaults.init(" + "suiteName: b)"
        let source = """
            let one = \(plain)
            let two = \(viaInit)!
            // let skipped = \(plain)
            /* let skipped = \(plain)
               let skipped = \(viaInit) */
            let three = /* inline \(plain) */ \(plain)
            """
        XCTAssertEqual(Self.rawSuiteSites(in: source), 3)
    }

    // MARK: - Ratchet

    /// Hand-rolled suites left per file, compared exactly; a file not listed
    /// must have none. After migrating a file, lower or delete its line. Each
    /// is a fresh suite name per test, and cfprefsd holds a descriptor for
    /// every such name until the whole run ends. `//` lines and `/* */` blocks don't count.
    private static let handRolled: [String: Int] = [
        "AlarmCivilClockIntegrationTests.swift": 1,
        "AlarmCivilClockPersistenceTests.swift": 1,
        "AlarmCorruptRecoveryTests.swift": 1,
        "AlarmFiringBalanceCurrencyTests.swift": 2,
        "AlarmFiringChargeFlyUpTests.swift": 1,
        "AlarmFiringCoordinatorTests.swift": 1,
        "AlarmFiringPresenterMissRuleTests.swift": 1,
        "AlarmFiringPresenterMissTests.swift": 1,
        "AlarmFiringPresenterQueueTests.swift": 1,
        "AlarmFiringPresenterSlotTests.swift": 1,
        "AlarmFiringPresenterTransitionTests.swift": 1,
        "AlarmFiringSnoozeHandoffTests.swift": 1,
        "AlarmFiringSnoozeRefundTests.swift": 1,
        "AlarmKitRouterAudioOwnerTests.swift": 1,
        "AlarmKitSnoozeIdentityTests.swift": 1,
        "AlarmKitSnoozeLoadFailureTests.swift": 1,
        "AlarmListPriceCurrencyTests.swift": 2,
        "AlarmOccurrenceFinishSessionTests.swift": 1,
        "AlarmPriceTierTests.swift": 1,
        "AlarmRecoveryAcceptanceTests.swift": 2,
        "AlarmRecoveryGuardTests.swift": 1,
        "AlarmRepeatModeTests.swift": 1,
        "AlarmSchedulerPaidSnoozeRearmTests.swift": 1,
        "AlarmThemeImageLifetimeTests.swift": 1,
        "AlarmViewModelLocalizationTests.swift": 1,
        "AlarmsListIndexTests.swift": 1,
        "AlarmsListSoundNameTests.swift": 1,
        "AlarmsListZeroBalanceAndWrapTests.swift": 1,
        "AppBannerPostingTests.swift": 1,
        "AppDelegateSnoozeDiagnosticTests.swift": 1,
        "AppLoggerSinkTests.swift": 1,
        "BalanceLedgerDecimalTests.swift": 1,
        "BalanceLedgerSourceOfTruthTests.swift": 2,
        "BalanceServiceMoneyAPITests.swift": 1,
        "CreateAlarmCivilClockTests.swift": 1,
        "CreateAlarmPermissionTests.swift": 1,
        "CreateAlarmRepeatValidityTests.swift": 1,
        "CreateAlarmViewModelPreviewTests.swift": 1,
        "CriticalWarningCenterTests.swift": 1,
        "DepositCatalogCurrencyTests.swift": 1,
        "EditorPriceCurrencyTests.swift": 1,
        "FiringCopyTests.swift": 1,
        "FiringDirectPurchaseTerminalTests.swift": 1,
        "FiringTopUpAutoResumeTests.swift": 1,
        "FiringTopUpCatalogTests.swift": 1,
        "MissingAlarmNotificationAudioTests.swift": 1,
        "PenaltyDisplayColorTests.swift": 1,
        "ReferralEntryPointVisibilityTests.swift": 1,
        "ReferralFriendCodeApplyTests.swift": 1,
        "ReferralPersonalCodeTests.swift": 1,
        "ReferralServiceTests.swift": 1,
        "SettingsPriceCurrencyTests.swift": 1,
        "SettingsReferralIsolationTests.swift": 1,
        "SettingsScreenCopyTests.swift": 1,
        "SettingsSectionsTests.swift": 1,
        "SettingsSubtitleRowHeightTests.swift": 1,
        "SettingsViewModelTests.swift": 1,
        "SnoozeAffordabilityTests.swift": 2,
        "SnoozePriceScaleStoreTests.swift": 1,
        "SoundThemePickerCatalogueTests.swift": 1,
        "StatisticsCurrencyTests.swift": 1,
        "StatisticsDataHealthTests.swift": 1,
        "StatisticsHeatmapCurrencyTests.swift": 1,
        "StatisticsSnapshotTests.swift": 1,
        "StoreKitCopyTests.swift": 1,
        "StoreKitPurchaseCancellationTests.swift": 1,
        "StoreKitPurchaseCrashRecoveryTests.swift": 1,
        "StoreKitVerifiedPurchaseTests.swift": 1,
        "ThemeServiceTests.swift": 1,
        "TopUpDisplayAmountTests.swift": 1,
        "TopUpRestoreServiceTests.swift": 1,
        "TopUpSuccessCurrencyTests.swift": 1,
        "TrackedSnoozeTestSupport.swift": 1,
        "TransactionCurrencyCodableTests.swift": 1,
        "UITourWarningRoutesTests.swift": 1,
        "VolumePickerInteractionTests.swift": 1,
        "WakeDayIdentityTests.swift": 1,
        "WakeEventStoreTests.swift": 1,
        "WakeHistoryAvailabilityTests.swift": 1,
        "WakeHistoryHostedLayoutTests.swift": 1,
        "WalletBalanceCurrencyTests.swift": 2
    ]
    /// Both spellings of the initializer; split so this file does not match itself.
    private static let needles = ["UserDefaults(" + "suiteName", "UserDefaults.init(" + "suiteName"]

    /// Raw suite sites in `text`, not counting `/* */` blocks or `//` lines.
    private static func rawSuiteSites(in text: String) -> Int {
        let code = text.replacingOccurrences(of: #"/\*[\s\S]*?\*/"#, with: " ", options: .regularExpression)
        return code.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .reduce(0) { sum, line in
                sum + needles.reduce(0) { $0 + line.components(separatedBy: $1).count - 1 }
            }
    }

    func testHandRolledSuitesMatchTheAllowlist() throws {
        let sources = try Self.testSources()
        XCTAssertGreaterThan(sources.count, 50, "found \(sources.count) sources — the scan would be vacuous")

        let found = sources.compactMapValues { text -> Int? in
            let count = Self.rawSuiteSites(in: text)
            return count > 0 ? count : nil
        }
        let offenders = Set(found.keys).union(Self.handRolled.keys)
            .filter { found[$0, default: 0] != Self.handRolled[$0, default: 0] }
            .sorted()
            .map { "\($0): \(found[$0, default: 0]) raw, allowlist \(Self.handRolled[$0, default: 0])" }
        XCTAssertEqual(
            offenders, [],
            "UserDefaults(suiteName:) by hand — use makeIsolatedDefaults()/makeIsolatedSuite(); "
                + "after migrating a file, lower or delete its allowlist line"
        )
    }

    /// Every test source except the helper, read from the checkout this file
    /// was compiled from (`#filePath`; no subprocess on the simulator), the
    /// same technique as `AlarmEditorCopyTests.alarmSourceDirectory()`.
    private static func testSources(filePath: StaticString = #filePath) throws -> [String: String] {
        let root = URL(fileURLWithPath: "\(filePath)").deletingLastPathComponent()
        let exempt: Set<String> = ["IsolatedDefaultsTestSupport.swift", "IsolatedDefaultsTestSupportTests.swift"]
        let files = (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL } ?? [])
            .filter { $0.pathExtension == "swift" && !exempt.contains($0.lastPathComponent) }
        var sources: [String: String] = [:]
        for file in files {
            sources[file.lastPathComponent] = try String(contentsOf: file, encoding: .utf8)
        }
        return sources
    }
}
