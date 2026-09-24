import XCTest

/// Keys in the host app's defaults domain that the guard below ignores.
///
/// Both are written by the test host, not by a test, and neither is written at
/// a moment a test controls. PR #826 (#814) measured both as already present at
/// `testBundleWillStart`, before the first test, but "already present" was one
/// run's timing, not a promise:
///
/// - `SKTransactionUpdatesLastChecked` is StoreKit's own bookkeeping. It is
///   written once `AppDelegate` starts the `Transaction.updates` listener, off
///   the main thread and on StoreKit's schedule. A write that lands inside a
///   test's window would fail that test for nothing the test did.
/// - `balance_ledger_opening` is written by `BalanceService.shared` on its first
///   read (production behaviour: the wallet adopts its opening balance). The
///   host normally reads it at launch, but a test that builds a view model on
///   the default `.shared` wallet — `AlarmFiringViewModelTests.testPenaltyFor*`
///   do — is a first read if it wins that race.
///
/// What allowing them costs: a test that writes one of these two keys goes
/// unseen. Neither is a key a test has any business writing, and the keys a
/// regression would actually bring back (`user_balance`, `stored_transactions`,
/// `stored_alarms`, `wake_days`, `wake_times`) are all still watched.
let appDefaultsHostOwnedKeys: Set<String> = [
    "SKTransactionUpdatesLastChecked",
    "balance_ledger_opening"
]

/// How one snapshot of a defaults domain differs from another, key by key.
///
/// Values are compared with `isEqual`, not by key presence: every property-list
/// type the domain can hold (`Data`, `Date`, number, string, array, dictionary)
/// bridges to an `NSObject` with value equality, so a test that rewrites
/// `user_balance` from 100 to 150 shows up as `changed`.
struct AppDefaultsDomainDrift {
    let added: [String]
    let removed: [String]
    let changed: [String]

    init(from before: [String: Any], to after: [String: Any], ignoring ignored: Set<String>) {
        let beforeKeys = Set(before.keys).subtracting(ignored)
        let afterKeys = Set(after.keys).subtracting(ignored)
        added = afterKeys.subtracting(beforeKeys).sorted()
        removed = beforeKeys.subtracting(afterKeys).sorted()
        changed = beforeKeys.intersection(afterKeys).filter { key in
            guard let old = before[key] as? NSObject, let new = after[key] as? NSObject else {
                // Not a plist object: nothing to compare by value, so it counts
                // as moved rather than being waved through.
                return true
            }
            return !old.isEqual(new)
        }.sorted()
    }

    var isEmpty: Bool {
        added.isEmpty && removed.isEmpty && changed.isEmpty
    }
}

/// Fails the test when it moved any key in the host app's real
/// `UserDefaults.standard` domain (#830).
///
/// # Why
///
/// PR #826 (#814) took four test classes off `.standard`: after it, the app
/// domain ends the suite holding only `appDefaultsHostOwnedKeys`. Nothing kept
/// it that way — a view model built with its `.shared` defaults and then made
/// to `snooze()`, `dismiss()` or `save()` would write the real user's wallet or
/// alarms again with every test still green.
///
/// # How
///
/// Each test is compared with itself, never with the suite: snapshot in
/// `setUp`, `assertUntouched()` in `tearDown`. A baseline taken once per run
/// would depend on which tests ran first, which is why #826's census could
/// only print and not fail.
///
/// The domain read is `persistentDomain(forName:)` for the host's bundle id,
/// not `dictionaryRepresentation()`: the latter merges NSGlobalDomain and the
/// registration domain, which the app does not own (#779). That this read sees
/// a write to `.standard` in the same process at all is pinned by
/// `AppDefaultsDomainGuardTests`, so the guard cannot quietly degrade into
/// comparing `[:]` with `[:]`.
///
/// # What it cannot see
///
/// - A write of the value that is already there. Snapshots compare values, so
///   a re-save of the same bytes is invisible. The domain is clean now, so a
///   regression adds a key rather than rewriting one — but a test that writes
///   after an earlier test left the same value behind will not be caught here.
/// - A write that the test undoes before `tearDown` (write, assert, restore).
/// - Anything written to the two host keys (see `appDefaultsHostOwnedKeys`).
/// - Work the test leaves queued that writes after `tearDown` returns. That
///   lands in a later test's window — and fails there, under the wrong name.
struct AppDefaultsDomainGuard {

    private let domain: String?
    private let before: [String: Any]

    init() {
        domain = Bundle.main.bundleIdentifier
        before = Self.snapshot(of: domain)
    }

    /// What has moved since `init`, host keys excluded.
    func drift() -> AppDefaultsDomainDrift {
        AppDefaultsDomainDrift(
            from: before,
            to: Self.snapshot(of: domain),
            ignoring: appDefaultsHostOwnedKeys
        )
    }

    func assertUntouched(file: StaticString = #filePath, line: UInt = #line) {
        guard let domain else {
            XCTFail(
                """
                Bundle.main has no bundle identifier — this test is not running inside the host \
                app, so the app defaults domain was never measured
                """,
                file: file, line: line
            )
            return
        }
        let moved = self.drift()
        guard !moved.isEmpty else { return }
        XCTFail(
            """
            this test moved the real UserDefaults.standard (domain `\(domain)`): \
            added \(moved.added), removed \(moved.removed), changed \(moved.changed). \
            Something in it is back on a `.shared` store or `.standard` — build the store over \
            the test's own suite (#814, #830)
            """,
            file: file, line: line
        )
    }

    private static func snapshot(of domain: String?) -> [String: Any] {
        guard let domain else { return [:] }
        return UserDefaults.standard.persistentDomain(forName: domain) ?? [:]
    }
}
