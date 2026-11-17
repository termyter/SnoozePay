import XCTest

/// A clean `UserDefaults` suite for one test, without leaking cfprefsd (#1118).
///
/// What was measured on the gate simulator (cfprefsd restarted before each
/// run, 50 suites per run, its descriptors sampled while the run was live):
/// cfprefsd keeps one open descriptor on `Library/Preferences` for every
/// suite *name* the test host has written more than once, until the host
/// process exits. `removePersistentDomain`, emptying the keys, deleting the
/// plist, releasing the `UserDefaults` — none of them gives it back (all +53).
/// The limit is 256 and a full `SnoozePayTests` run is one process, so
/// `"<Class>-<UUID>"` per test exhausted it within a single run (#1108).
///
/// Reusing names is what works: 50 tests on one name held +1. So suites come
/// from a small pool of fixed names, emptied when handed out and again when
/// the test ends. A test that needs two suites at once gets two slots.
///
/// The price of reuse: an object from an earlier test that still writes
/// asynchronously into its old instance would write into the slot. Emptying
/// on hand-out bounds that to work that is still running when the next test
/// starts.
extension XCTestCase {

    /// An empty suite that is emptied again and returned to the pool after the test.
    func makeIsolatedDefaults() -> UserDefaults {
        makeIsolatedSuite().defaults
    }

    /// Same as ``makeIsolatedDefaults()``, plus the suite name, for tests that
    /// open a second instance on the same suite to prove persistence.
    ///
    /// Teardown blocks run after the test method and *before* `tearDown()`;
    /// a `tearDown()` that writes to these defaults writes into a free slot.
    func makeIsolatedSuite() -> (defaults: UserDefaults, name: String) {
        let slot = IsolatedDefaultsPool.acquire()
        let name = IsolatedDefaultsPool.suiteName(slot)
        guard let defaults = UserDefaults(suiteName: name) else {
            preconditionFailure("UserDefaults refused suite name \(name)")
        }
        defaults.removePersistentDomain(forName: name)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: name)
            IsolatedDefaultsPool.release(slot)
        }
        return (defaults, name)
    }
}

/// Which pool slots are handed out to the running test.
enum IsolatedDefaultsPool {
    private static var inUse: Set<Int> = []

    static func suiteName(_ slot: Int) -> String { "SnoozePayTests.isolated.\(slot)" }

    static func acquire() -> Int {
        let slot = (0...).first { !inUse.contains($0) } ?? 0
        inUse.insert(slot)
        return slot
    }

    static func release(_ slot: Int) { inUse.remove(slot) }

    static var slotsInUse: Int { inUse.count }
}
