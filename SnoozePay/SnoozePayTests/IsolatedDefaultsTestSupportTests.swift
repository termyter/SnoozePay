import XCTest

/// Pins `makeIsolatedDefaults` (#1118): every test starts on an empty suite,
/// the suite is emptied and returned when the test ends, and the number of
/// hand-rolled suites in this target only goes down.
final class IsolatedDefaultsTestSupportTests: XCTestCase {

    func testSlotLeftDirtyIsEmptiedWhenHandedOut() throws {
        // The pool hands out the lowest free slot, so this is the one we get next.
        let peek = IsolatedDefaultsPool.acquire()
        IsolatedDefaultsPool.release(peek)
        let stale = try XCTUnwrap(UserDefaults(suiteName: IsolatedDefaultsPool.suiteName(peek)))
        stale.set(1, forKey: "stale")
        XCTAssertNotNil(stale.object(forKey: "stale"), "pollution did not land — the check below would be vacuous")

        let (defaults, name) = makeIsolatedSuite()

        XCTAssertEqual(name, IsolatedDefaultsPool.suiteName(peek))
        XCTAssertNil(defaults.object(forKey: "stale"))
    }

    /// Teardown blocks run last-registered-first, so the check registered
    /// before the helper runs after the helper's own cleanup.
    func testSuiteIsEmptiedAndReturnedAfterTheTestEnds() {
        let slotsBefore = IsolatedDefaultsPool.slotsInUse
        let created = NSMutableArray()
        addTeardownBlock {
            XCTAssertEqual(created.count, 1, "the suite was never created — nothing to check")
            for case let name as String in created {
                let domain = UserDefaults(suiteName: name)?.persistentDomain(forName: name) ?? [:]
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

    func testSecondInstanceOnTheSameSuiteSeesTheWrite() {
        let (defaults, name) = makeIsolatedSuite()
        defaults.set(42, forKey: "probe")
        XCTAssertEqual(UserDefaults(suiteName: name)?.integer(forKey: "probe"), 42)
    }

    func testTwoSuitesInOneTestAreSeparate() {
        let first = makeIsolatedSuite()
        let second = makeIsolatedSuite()
        first.defaults.set(1, forKey: "probe")

        XCTAssertNotEqual(first.name, second.name)
        XCTAssertNil(second.defaults.object(forKey: "probe"))
    }

    // MARK: - Ratchet

    /// Hand-rolled suites still in the target. Lower it when you migrate a
    /// file to `makeIsolatedDefaults`; never raise it. Each one is a fresh
    /// suite name per test, and cfprefsd holds a descriptor for every such
    /// name until the whole run ends.
    private static let handRolledCeiling = 108
    private static let needle = "UserDefaults(" + "suiteName"  // split so this file does not match itself

    func testHandRolledSuitesOnlyGoDown() throws {
        let sources = try Self.testSources()
        XCTAssertGreaterThan(sources.count, 50, "found \(sources.count) sources — the scan would be vacuous")

        let perFile = sources.compactMapValues { text -> Int? in
            let count = text.components(separatedBy: Self.needle).count - 1
            return count > 0 ? count : nil
        }
        let total = perFile.values.reduce(0, +)
        let listing = perFile.sorted { $0.value > $1.value }.map { "\($0.key): \($0.value)" }
        XCTAssertLessThanOrEqual(
            total, Self.handRolledCeiling,
            "\(total) hand-rolled suites (ceiling \(Self.handRolledCeiling)); use makeIsolatedDefaults. \(listing)"
        )
        if total < Self.handRolledCeiling {
            print("[#1118] \(total) hand-rolled suites < ceiling \(Self.handRolledCeiling) — lower the ceiling")
        }
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
