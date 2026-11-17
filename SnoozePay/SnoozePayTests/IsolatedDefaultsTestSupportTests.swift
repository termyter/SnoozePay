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
            let three = \(plain)
            let four = /* inline \(plain) */ \(plain)
            """
        // A greedy `/\*[\s\S]*\*/` would swallow `three` along with both comments and count 3.
        XCTAssertEqual(Self.rawSuiteSites(in: source), 4)
    }

    func testRatchetCatchesSpacedSplitAndInferredSpellings() {
        let key = "suite" + "Name"
        let source = """
            let one = UserDefaults (\(key): a)
            let two = UserDefaults.init( \(key): b)
            let three: UserDefaults? = .init(\(key): c)
            let four = UserDefaults
                (\(key): d)
            let none = UserDefaults.standard
            let alsoNone = UserDefaults()
            """
        XCTAssertEqual(Self.rawSuiteSites(in: source), 4)
    }

    func testRatchetCountsUserDefaultsSubclasses() {
        let key = "suite" + "Name"
        let sources = [
            "a.swift": "private final class LogDefaults: UserDefaults, @unchecked Sendable {}",
            "b.swift": """
                final class StrictDefaults : UserDefaults {}
                class StricterDefaults: StrictDefaults {}
                // class CommentedDefaults: UserDefaults {}
                let one = LogDefaults(\(key): a)
                let two = StricterDefaults.init(\(key): b)
                let three = StrictDefaults
                    (\(key): c)
                let none = NotADefaults(\(key): d)
                override init?(\(key) name: String?) { super.init(\(key): name) }
                """
        ]
        let subclasses = Self.defaultsSubclasses(in: sources)
        XCTAssertEqual(subclasses, ["LogDefaults", "StrictDefaults", "StricterDefaults"])
        XCTAssertEqual(Self.rawSuiteSites(in: sources["b.swift"] ?? "", subclasses: subclasses), 3)
    }

    /// The real subclasses are found, so the scan above is not vacuous on this checkout.
    func testRatchetFindsTheSubclassesInThisTarget() throws {
        let subclasses = Self.defaultsSubclasses(in: try Self.testSources())
        XCTAssertTrue(
            subclasses.isSuperset(of: ["RecoveryStorageDefaults", "FinishWriteRefusingDefaults", "WriteLogDefaults"]),
            "found \(subclasses.sorted())"
        )
    }

    // MARK: - Ratchet

    /// Hand-rolled suites left per file, compared exactly; a file not listed
    /// must have none. After migrating a file, lower or delete its line. Each
    /// is a fresh suite name per test, and cfprefsd holds a descriptor for
    /// every such name until the whole run ends. `//` lines and `/* */` blocks don't count.
    private static let handRolled: [String: Int] = [
        "AlarmCorruptRecoveryTests.swift": 1,
        "AlarmFiringBalanceCurrencyTests.swift": 2,
        "AlarmFiringChargeFlyUpTests.swift": 1,
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
        "AlarmRecoveryAcceptanceTests.swift": 2,
        "AlarmRecoveryGuardTests.swift": 1,
        "AlarmsListIndexTests.swift": 1,
        "AppDelegateSnoozeDiagnosticTests.swift": 1,
        "AppLoggerSinkTests.swift": 1,
        "BalanceLedgerDecimalTests.swift": 1,
        "CreateAlarmViewModelPreviewTests.swift": 1,
        "DepositCatalogCurrencyTests.swift": 1,
        "EditorPriceCurrencyTests.swift": 1,
        "FiringDirectPurchaseTerminalTests.swift": 1,
        "FiringTopUpCatalogTests.swift": 1,
        "MissingAlarmNotificationAudioTests.swift": 1,
        "PenaltyDisplayColorTests.swift": 1,
        "ReferralPersonalCodeTests.swift": 1,
        "ReferralServiceTests.swift": 1,
        "SettingsReferralIsolationTests.swift": 1,
        "SettingsSubtitleRowHeightTests.swift": 1,
        "StatisticsSnapshotTests.swift": 1,
        "StoreKitPurchaseCancellationTests.swift": 1,
        "TopUpDisplayAmountTests.swift": 1,
        "TopUpSuccessCurrencyTests.swift": 1,
        "VolumePickerInteractionTests.swift": 1,
        "WakeHistoryHostedLayoutTests.swift": 1,
        "WalletBalanceCurrencyTests.swift": 2
    ]
    /// The initializer of `UserDefaults` or of any of its `subclasses`, with or
    /// without `.init`, with any whitespace (newlines included) around `.init`
    /// and `(`, plus the inferred `.init(suiteName:`. One alternation, so
    /// `UserDefaults.init(suiteName:` is one match, not two. A subclass built on
    /// a pool name still counts: only the helper builds those. `super.init(suiteName:)`
    /// does not: it forwards the name of whoever builds the subclass, which is counted.
    private static func rawSitePattern(subclasses: Set<String>) -> NSRegularExpression? {
        let names = (["UserDefaults"] + subclasses.sorted()).joined(separator: "|")
        return try? NSRegularExpression(
            pattern: #"(?:"# + names + #")\s*(?:\.init)?\s*\(\s*suiteName|(?<!super)\.init\s*\(\s*suiteName"#
        )
    }

    /// `text` without `/* */` blocks and `//` lines.
    private static func stripComments(_ text: String) -> String {
        text.replacingOccurrences(of: #"/\*[\s\S]*?\*/"#, with: " ", options: .regularExpression)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// Classes declared as `UserDefaults` subclasses, directly or through
    /// another subclass, anywhere in `sources` — not guessed by name suffix.
    private static func defaultsSubclasses(in sources: [String: String]) -> Set<String> {
        let declaration = try? NSRegularExpression(pattern: #"\bclass\s+(\w+)\s*:\s*(\w+)"#)
        var parents: [String: String] = [:]
        for text in sources.values.map(stripComments) {
            let range = NSRange(text.startIndex..., in: text)
            for match in declaration?.matches(in: text, range: range) ?? [] {
                guard let name = Range(match.range(at: 1), in: text), let parent = Range(match.range(at: 2), in: text)
                else { continue }
                parents[String(text[name])] = String(text[parent])
            }
        }
        var found: Set<String> = []
        var grew = true
        while grew {
            let next = Set(parents.filter { $0.value == "UserDefaults" || found.contains($0.value) }.keys)
            grew = next.count > found.count
            found = next
        }
        return found
    }

    /// Raw suite sites in `text`, not counting `/* */` blocks or `//` lines.
    /// A pattern that failed to compile counts 0, which the tests above catch.
    private static func rawSuiteSites(in text: String, subclasses: Set<String> = []) -> Int {
        let code = stripComments(text)
        let pattern = rawSitePattern(subclasses: subclasses)
        return pattern?.numberOfMatches(in: code, range: NSRange(code.startIndex..., in: code)) ?? 0
    }

    func testHandRolledSuitesMatchTheAllowlist() throws {
        let sources = try Self.testSources()
        XCTAssertGreaterThan(sources.count, 50, "found \(sources.count) sources — the scan would be vacuous")

        let subclasses = Self.defaultsSubclasses(in: sources)
        let found = sources.compactMapValues { text -> Int? in
            let count = Self.rawSuiteSites(in: text, subclasses: subclasses)
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
