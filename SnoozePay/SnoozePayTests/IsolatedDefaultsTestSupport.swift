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
/// Rules for callers:
/// - Never write `UserDefaults(suiteName:)` in a test; the ratchet in
///   `IsolatedDefaultsTestSupportTests` counts them per file. To prove
///   persistence across a relaunch, take the name from `makeIsolatedSuite()`
///   and reopen it with `reopenIsolatedDefaults(named:)`.
/// - Teardown blocks run after the test method and *before* `tearDown()`, so
///   a `tearDown()` that writes to these defaults writes into a freed slot.
/// - Do not keep the returned defaults in a `static`: the slot is handed to
///   the next test, and the static would read and write its data.
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
    /// reopen the suite (``reopenIsolatedDefaults(named:)``) to prove persistence.
    func makeIsolatedSuite() -> (defaults: UserDefaults, name: String) {
        let lease = IsolatedDefaultsPool.checkOut()
        addTeardownBlock { IsolatedDefaultsPool.checkIn(lease.slot) }
        return (lease.defaults, IsolatedDefaultsPool.suiteName(lease.slot))
    }

    /// A second, independent instance on a suite from ``makeIsolatedSuite()``,
    /// standing in for the app after a relaunch. Cleanup stays with the lease.
    func reopenIsolatedDefaults(named name: String) -> UserDefaults {
        // A hand-rolled name here would be the per-test leak again, under a new spelling.
        precondition(
            IsolatedDefaultsPool.isPoolName(name),
            "\(name) is not a pool suite — take it from makeIsolatedSuite()"
        )
        guard let defaults = UserDefaults(suiteName: name) else {
            preconditionFailure("UserDefaults refused suite name \(name)")
        }
        return defaults
    }
}

/// Which pool slots are handed out to the running test.
@MainActor
enum IsolatedDefaultsPool {
    private static var inUse: Set<Int> = []

    static var slotsInUse: Int { inUse.count }

    private static let namePrefix = "SnoozePayTests.isolated."

    static func suiteName(_ slot: Int) -> String { namePrefix + "\(slot)" }

    /// Whether `name` is one of the pool's own suites, `suiteName(n)` for some `n >= 0`.
    static func isPoolName(_ name: String) -> Bool {
        guard name.hasPrefix(namePrefix), let slot = Int(name.dropFirst(namePrefix.count)) else { return false }
        return slot >= 0 && suiteName(slot) == name
    }

    /// The lowest free slot, emptied of whatever a previous test left in it.
    static func checkOut() -> (slot: Int, defaults: UserDefaults) {
        var slot = 0
        while inUse.contains(slot) { slot += 1 }
        inUse.insert(slot)
        let name = suiteName(slot)
        guard let defaults = UserDefaults(suiteName: name) else {
            preconditionFailure("UserDefaults refused suite name \(name)")
        }
        defaults.removePersistentDomain(forName: name)
        return (slot, defaults)
    }

    /// Empties the slot's suite and frees the slot for the next hand-out.
    /// A slot that is not handed out is left alone: a second check-in must not
    /// wipe whatever the slot's next owner, or a test peeking at it, put there.
    static func checkIn(_ slot: Int) {
        guard inUse.remove(slot) != nil else { return }
        let name = suiteName(slot)
        UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
    }
}
