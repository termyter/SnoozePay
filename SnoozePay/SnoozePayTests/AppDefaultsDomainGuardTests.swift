import XCTest

/// Holds `AppDefaultsDomainGuard` to its contract (#830). Without these, the
/// guard could compare the wrong domain — `[:]` with `[:]` — and every class it
/// is attached to would stay green whatever it wrote.
final class AppDefaultsDomainGuardTests: XCTestCase {

    // MARK: - The diff

    func testDriftSortsKeysIntoAddedRemovedAndChanged() {
        let drift = AppDefaultsDomainDrift(
            from: ["kept": 1, "gone": "x", "moved": 100.0],
            to: ["kept": 1, "moved": 150.0, "new": true],
            ignoring: []
        )

        XCTAssertEqual(drift.added, ["new"])
        XCTAssertEqual(drift.removed, ["gone"])
        XCTAssertEqual(drift.changed, ["moved"])
        XCTAssertFalse(drift.isEmpty)
    }

    /// Values, not key presence: a wallet rewritten from one balance to another
    /// keeps its key, and a key-set diff would call that untouched.
    func testDriftComparesEveryPlistTypeByValue() {
        let date = Date(timeIntervalSince1970: 1_000)
        let before: [String: Any] = [
            "data": Data([1, 2]),
            "date": date,
            "array": [1, 2],
            "dict": ["a": 1],
            "string": "a"
        ]
        let sameValues: [String: Any] = [
            "data": Data([1, 2]),
            "date": Date(timeIntervalSince1970: 1_000),
            "array": [1, 2],
            "dict": ["a": 1],
            "string": "a"
        ]
        let newValues: [String: Any] = [
            "data": Data([1, 3]),
            "date": date.addingTimeInterval(1),
            "array": [1, 2, 3],
            "dict": ["a": 2],
            "string": "b"
        ]

        XCTAssertTrue(
            AppDefaultsDomainDrift(from: before, to: sameValues, ignoring: []).isEmpty,
            "equal values in fresh instances must not count as a change"
        )
        XCTAssertEqual(
            AppDefaultsDomainDrift(from: before, to: newValues, ignoring: []).changed,
            ["array", "data", "date", "dict", "string"]
        )
    }

    func testDriftIgnoresTheHostOwnedKeysInEveryDirection() {
        let drift = AppDefaultsDomainDrift(
            from: ["SKTransactionUpdatesLastChecked": Date(timeIntervalSince1970: 0)],
            to: [
                "SKTransactionUpdatesLastChecked": Date(timeIntervalSince1970: 60),
                "balance_ledger_opening": 0.0
            ],
            ignoring: appDefaultsHostOwnedKeys
        )

        XCTAssertTrue(drift.isEmpty, "host keys moved: \(drift)")
    }

    // MARK: - The live domain

    /// The guard reads `persistentDomain(forName:)`, and this pins that the
    /// read sees a write to `.standard` made in the same process. If the
    /// domain name were wrong, both snapshots would be empty and this is the
    /// one test that would say so.
    func testGuardSeesAWriteToStandardAndItsRemoval() {
        let standard = UserDefaults.standard
        let probeKey = "test.830.probe"
        standard.removeObject(forKey: probeKey)
        let domainGuard = AppDefaultsDomainGuard()

        standard.set(UUID().uuidString, forKey: probeKey)
        defer { standard.removeObject(forKey: probeKey) }
        XCTAssertEqual(
            domainGuard.drift().added, [probeKey],
            "a key written to UserDefaults.standard is not in the domain the guard reads"
        )

        standard.removeObject(forKey: probeKey)
        let afterRemoval = domainGuard.drift()
        XCTAssertTrue(afterRemoval.isEmpty, "the probe is gone, yet the guard still sees \(afterRemoval)")
    }
}
