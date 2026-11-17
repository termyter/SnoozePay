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
/// - A `UserDefaults` subclass (fault injection, write logs) is built on a
///   pool suite by `makeIsolatedSuite(as:)`, or by `IsolatedDefaultsPool.checkOut(as:)`
///   in a fixture that is not a test case and checks the slot back in from its
///   `close()`. A subclass built with `(suiteName:)` in a test file is a raw
///   site like any other — even on a pool name — and the ratchet counts it.
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
        addTeardownBlock { IsolatedDefaultsPool.checkIn(lease) }
        return (lease.defaults, lease.name)
    }

    /// Same as ``makeIsolatedSuite()``, as an instance of a `UserDefaults` subclass.
    func makeIsolatedSuite<Defaults: IsolatedDefaultsSubclass>(
        as type: Defaults.Type
    ) -> (defaults: Defaults, name: String) {
        let lease = IsolatedDefaultsPool.checkOut(as: type)
        addTeardownBlock { IsolatedDefaultsPool.checkIn(lease) }
        return (lease.defaults, lease.name)
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

/// A `UserDefaults` subclass the pool can build on its own suites. The
/// subclass must spell out `override init?(suiteName:)` forwarding to `super`:
/// the inherited initializer does not satisfy the requirement.
protocol IsolatedDefaultsSubclass: UserDefaults {
    init?(suiteName suitename: String?)
}

/// One hand-out of a pool slot. Only the lease that is current for its slot
/// can check it back in: once the slot has been handed out again, an older
/// lease for the same slot is stale and its check-in does nothing.
struct IsolatedDefaultsLease<Defaults: UserDefaults> {
    let slot: Int
    let defaults: Defaults
    fileprivate let token: Int

    @MainActor var name: String { IsolatedDefaultsPool.suiteName(slot) }
}

/// Which pool slots are handed out to the running test, and to which lease.
@MainActor
enum IsolatedDefaultsPool {
    /// Slot → token of the lease that holds it.
    private static var owners: [Int: Int] = [:]
    private static var lastToken = 0

    static var slotsInUse: Int { owners.count }

    private static let namePrefix = "SnoozePayTests.isolated."

    static func suiteName(_ slot: Int) -> String { namePrefix + "\(slot)" }

    /// Whether `name` is one of the pool's own suites, `suiteName(n)` for some `n >= 0`.
    static func isPoolName(_ name: String) -> Bool {
        guard name.hasPrefix(namePrefix), let slot = Int(name.dropFirst(namePrefix.count)) else { return false }
        return slot >= 0 && suiteName(slot) == name
    }

    /// The lowest free slot, emptied of whatever a previous test left in it.
    static func checkOut() -> IsolatedDefaultsLease<UserDefaults> {
        checkOut { UserDefaults(suiteName: $0) }
    }

    /// ``checkOut()``, with the slot's suite opened as `Defaults`. The caller
    /// owns the slot until it hands the lease back with ``checkIn(_:)``.
    static func checkOut<Defaults: IsolatedDefaultsSubclass>(
        as type: Defaults.Type
    ) -> IsolatedDefaultsLease<Defaults> {
        checkOut { Defaults(suiteName: $0) }
    }

    private static func checkOut<Defaults: UserDefaults>(
        opening open: (String) -> Defaults?
    ) -> IsolatedDefaultsLease<Defaults> {
        var slot = 0
        while owners[slot] != nil { slot += 1 }
        lastToken += 1
        owners[slot] = lastToken
        let name = suiteName(slot)
        // Emptied through a plain instance: a subclass may log or refuse writes.
        UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
        guard let defaults = open(name) else {
            preconditionFailure("\(Defaults.self) refused suite name \(name)")
        }
        return IsolatedDefaultsLease(slot: slot, defaults: defaults, token: lastToken)
    }

    /// Empties the slot's suite and frees the slot for the next hand-out.
    /// Only the slot's current lease does that: a second check-in, or a stale
    /// one after the slot went to a new owner, must not wipe the new owner's data.
    static func checkIn<Defaults>(_ lease: IsolatedDefaultsLease<Defaults>) {
        guard owners[lease.slot] == lease.token else { return }
        owners[lease.slot] = nil
        let name = suiteName(lease.slot)
        UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
    }
}
