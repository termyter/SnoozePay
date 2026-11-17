import XCTest

/// Pins `makeIsolatedDefaults` (#1118): every test starts on an empty suite,
/// a returned slot is handed out again under the same name — the whole fd fix
/// rests on that — and hand-rolled suites only disappear, file by file.
final class IsolatedDefaultsTestSupportTests: XCTestCase {

    func testSlotLeftDirtyIsEmptiedWhenHandedOut() {
        // The pool hands out the lowest free slot, so this is the one we get next.
        let peek = IsolatedDefaultsPool.checkOut()
        IsolatedDefaultsPool.checkIn(peek)
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
        IsolatedDefaultsPool.checkIn(first)

        let second = IsolatedDefaultsPool.checkOut()
        defer { IsolatedDefaultsPool.checkIn(second) }

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

    /// `checkOut(as:)` empties the slot through a plain instance, not through the
    /// subclass it hands out: a subclass that refuses the wipe still starts empty.
    func testSubclassThatRefusesTheWipeStillStartsOnAnEmptySlot() {
        let peek = IsolatedDefaultsPool.checkOut()
        IsolatedDefaultsPool.checkIn(peek)
        let stale = reopenIsolatedDefaults(named: IsolatedDefaultsPool.suiteName(peek.slot))
        stale.set(1, forKey: "stale")
        XCTAssertNotNil(stale.object(forKey: "stale"), "pollution did not land — the check below would be vacuous")

        let (defaults, name) = makeIsolatedSuite(as: WipeRefusingDefaults.self)

        XCTAssertEqual(name, IsolatedDefaultsPool.suiteName(peek.slot))
        XCTAssertNil(defaults.object(forKey: "stale"), "the slot was emptied through the subclass, which refuses")
        defaults.set(2, forKey: "probe")
        defaults.removePersistentDomain(forName: name)
        XCTAssertEqual(defaults.integer(forKey: "probe"), 2, "the subclass wiped — the check above would be vacuous")
    }

    /// A slot nobody holds is not wiped or "freed" by a stray check-in.
    func testCheckInOfASlotNotHandedOutLeavesItAlone() {
        let peek = IsolatedDefaultsPool.checkOut()
        IsolatedDefaultsPool.checkIn(peek)
        let name = IsolatedDefaultsPool.suiteName(peek.slot)
        let outside = reopenIsolatedDefaults(named: name)
        defer { outside.removePersistentDomain(forName: name) }
        outside.set(1, forKey: "probe")
        let slotsBefore = IsolatedDefaultsPool.slotsInUse

        IsolatedDefaultsPool.checkIn(peek)

        XCTAssertEqual(outside.integer(forKey: "probe"), 1, "a check-in of a free slot wiped it")
        XCTAssertEqual(IsolatedDefaultsPool.slotsInUse, slotsBefore)
    }

    /// A fixture that checks in late, after its slot went to the next owner,
    /// must not free the slot or wipe what the new owner wrote.
    func testStaleCheckInLeavesTheSlotsNextOwnerAlone() {
        let stale = IsolatedDefaultsPool.checkOut()
        IsolatedDefaultsPool.checkIn(stale)
        let current = IsolatedDefaultsPool.checkOut()
        defer { IsolatedDefaultsPool.checkIn(current) }
        XCTAssertEqual(current.slot, stale.slot, "the slot was not reused — the check below would be vacuous")
        current.defaults.set(1, forKey: "probe")
        let slotsBefore = IsolatedDefaultsPool.slotsInUse

        IsolatedDefaultsPool.checkIn(stale)

        XCTAssertEqual(current.defaults.integer(forKey: "probe"), 1, "a stale check-in wiped the new owner's suite")
        XCTAssertEqual(IsolatedDefaultsPool.slotsInUse, slotsBefore, "a stale check-in freed the new owner's slot")
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
                let alsoNone = NotStrictDefaults(\(key): e)
                override init?(\(key) name: String?) { super.init(\(key): name) }
                """
        ]
        let subclasses = Self.defaultsSubclasses(in: sources)
        XCTAssertEqual(subclasses, ["LogDefaults", "StrictDefaults", "StricterDefaults"])
        // `NotStrictDefaults` is not a subclass: without `\b` it would count as `StrictDefaults`.
        XCTAssertEqual(Self.rawSuiteSites(in: sources["b.swift"] ?? "", subclasses: subclasses), 3)
    }

    /// Only `super.init` forwards; `Self.init` and `type.init` build a suite and count.
    /// A skip widened from `super` to any word before `.init` would miss both.
    func testRatchetCountsInitThroughSelfAndAMetatype() {
        let key = "suite" + "Name"
        let source = """
            static func make() -> Self? { Self.init(\(key): "a") }
            func make(_ type: UserDefaults.Type) -> UserDefaults? { type.init(\(key): "b") }
            override init?(\(key) name: String?) { super.init(\(key): name) }
            """
        XCTAssertEqual(Self.rawSuiteSites(in: source), 2)
    }

    /// A generic subclass, a module-qualified parent, and inits spelled with generic
    /// arguments or a module prefix. Without the optional `<...>` the generic sites
    /// fall through; `NotGenericDefaults` is not a subclass and must not count.
    func testRatchetCountsGenericAndModuleQualifiedSubclassInits() {
        let key = "suite" + "Name"
        let sources = [
            "a.swift": """
                final class GenericDefaults<Value>: UserDefaults {}
                class QualifiedDefaults: Foundation.UserDefaults {}
                """,
            "b.swift": """
                let one = GenericDefaults<Int>(\(key): a)
                let two = GenericDefaults<[String: Int]>.init(\(key): b)
                let three = SnoozePayTests.QualifiedDefaults(\(key): c)
                let four = Foundation.UserDefaults(\(key): d)
                let five = SnoozePayTests.GenericDefaults<Int>.init(\(key): e)
                let none = NotGenericDefaults<Int>(\(key): f)
                """
        ]
        let subclasses = Self.defaultsSubclasses(in: sources)
        XCTAssertEqual(subclasses, ["GenericDefaults", "QualifiedDefaults"])
        XCTAssertEqual(Self.rawSuiteSites(in: sources["b.swift"] ?? "", subclasses: subclasses), 5)
    }

    /// The `super.init` skip is the keyword only: a metatype held in a name that
    /// merely ends in `super` builds a suite and counts.
    func testRatchetSuperSkipIsTheKeywordOnly() {
        let key = "suite" + "Name"
        let source = """
            override init?(\(key) name: String?) { super.init(\(key): name) }
            let built = fromsuper.init(\(key): "a")
            """
        XCTAssertEqual(Self.rawSuiteSites(in: source), 1)
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
    /// must have none. Empty since batch 6: every test file is on the pool. A
    /// hand-rolled suite is a fresh name per test, and cfprefsd holds a descriptor
    /// for every such name until the whole run ends. `//` lines and `/* */` blocks
    /// don't count. Add a line here only with a reason the pool cannot serve.
    private static let handRolled: [String: Int] = [:]
    /// The initializer of `UserDefaults` or of any of its `subclasses`, with or
    /// without `.init`, with any whitespace (newlines included) around `.init`
    /// and `(`, plus the inferred `.init(suiteName:`. One alternation, so
    /// `UserDefaults.init(suiteName:` is one match, not two. Generic arguments
    /// (`Foo<Bar>(suiteName:`) and a module prefix (`SnoozePayTests.Foo(`) count
    /// too. A subclass built on a pool name still counts: only the helper builds
    /// those. `super.init(suiteName:)` does not — the keyword `super` only, not a
    /// name ending in it: it forwards the name of whoever builds the subclass, which is counted.
    private static func rawSitePattern(subclasses: Set<String>) -> NSRegularExpression? {
        let names = (["UserDefaults"] + subclasses.sorted()).joined(separator: "|")
        return try? NSRegularExpression(
            pattern: #"\b(?:"# + names + #")(?:\s*<[^<>()]*>)?\s*(?:\.init)?\s*\(\s*suiteName"#
                + #"|(?<!\bsuper)\.init\s*\(\s*suiteName"#
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
        let declaration = try? NSRegularExpression(
            pattern: #"\bclass\s+(\w+)\s*(?:<[^<>]*>)?\s*:\s*(?:\w+\s*\.\s*)?(\w+)"#
        )
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

/// Ignores `removePersistentDomain`, like a fault-injecting subclass might.
private final class WipeRefusingDefaults: UserDefaults, IsolatedDefaultsSubclass {
    // Spelled out: an inherited initializer does not witness `IsolatedDefaultsSubclass`.
    override init?(suiteName suitename: String?) { super.init(suiteName: suitename) }
    override func removePersistentDomain(forName domainName: String) {}
}
