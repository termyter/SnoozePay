import XCTest

/// The guard is only as strong as the spellings and keys it recognises, and no
/// copy suite asserts on it: every test that calls it would stay green if it
/// stopped matching. These tests are the only thing standing over it, which is
/// why they travelled here with it (#756) rather than staying in the one suite
/// that happened to grow them (#713, #757).
///
/// `assertNoKeysLeaked` never reads the catalogue — it compares strings — so
/// the keys below are spelled out rather than taken from a screen's table.
final class CopyTestSupportTests: XCTestCase {

    private static let volumeKey = "create_alarm.volume.title"
    private static let soundKey = "create_alarm.sound.title"

    /// A caps section label renders `Localized.text(key).uppercased()`, so a
    /// missed lookup reaches the screen as `CREATE_ALARM.VOLUME.TITLE` — both
    /// spellings have to be a failure.
    func testKeyLeakGuardCatchesLowerAndUpperCasedKeys() {
        let key = Self.volumeKey
        for leaked in [key, key.uppercased()] {
            // `strict` is already the default, but it is the whole contract
            // here: with it off, a guard that stopped matching would record
            // nothing and this test would pass. Written out so nobody turns it
            // off by habit. The matcher is the other half: without it the
            // expectation swallows ANY recorded failure, so the test would
            // prove only that the guard went red, not that it named the
            // spelling that reached the screen. The two arrive as `strict:` +
            // trailing `issueMatcher:` because no overload takes `options:` and
            // a trailing `issueMatcher:` together — a matcher can still ride
            // inside the options, which is what `issuesRecordedByGuard` does.
            XCTExpectFailure("the guard has to name «\(leaked)»", strict: true) {
                assertNoKeysLeaked([key], in: ["Громкость", leaked])
            } issueMatcher: { issue in
                issue.compactDescription.contains("«\(leaked)»")
            }
        }
    }

    /// The guard reports EVERY spelling that reached the screen, not just the
    /// first one it matches: a key that leaks into a plain label *and* a caps
    /// one is two call sites, and naming half of them sends the fixer to half
    /// the job. Nothing noticed when that was the case — going back to
    /// `spellings.first(where:)` still leaves the guard red, only with half the
    /// picture, so `testKeyLeakGuardCatchesLowerAndUpperCasedKeys` and every
    /// caller stay green (#757). Counting the reports is what tells the two
    /// loops apart.
    func testKeyLeakGuardReportsEverySpellingThatReachedTheScreen() {
        let key = Self.volumeKey

        let both = Self.issuesRecordedByGuard(over: ["Громкость", key, key.uppercased()], keys: [key])
        XCTAssertEqual(
            both.count, 2,
            "one key leaked in two spellings and the guard filed \(both.count) "
                + "report(s): \(Self.descriptions(of: both))"
        )
        for leaked in [key, key.uppercased()] {
            XCTAssertTrue(
                both.contains { $0.compactDescription.contains("«\(leaked)»") },
                "no report names «\(leaked)»: \(Self.descriptions(of: both))"
            )
        }

        // The other half of the contract, and the reason the count above is an
        // equality and not a `>= 2`: one spelling on screen stays one report.
        // A guard that reported both spellings of anything it matched would
        // satisfy the assertions above and be wrong about every real leak.
        for leaked in [key, key.uppercased()] {
            let single = Self.issuesRecordedByGuard(over: ["Громкость", leaked], keys: [key])
            XCTAssertEqual(
                single.count, 1,
                "«\(leaked)» leaked once and the guard filed \(single.count) "
                    + "report(s): \(Self.descriptions(of: single))"
            )
        }
    }

    /// The guard walks the whole key list. Every caller hands it a screen's
    /// entire table, and a guard that stopped at the first match would still go
    /// red on any real leak — naming one key while the rest of the screen was
    /// equally broken. `testKeyLeakGuardReportsEverySpellingThatReachedTheScreen`
    /// cannot see that: it passes a single key.
    func testKeyLeakGuardReportsEveryKeyThatLeaked() {
        let keys = [Self.volumeKey, Self.soundKey]

        let issues = Self.issuesRecordedByGuard(over: keys, keys: keys)
        XCTAssertEqual(
            issues.count, 2,
            "two keys leaked and the guard filed \(issues.count) "
                + "report(s): \(Self.descriptions(of: issues))"
        )
        for leaked in keys {
            XCTAssertTrue(
                issues.contains { $0.compactDescription.contains("«\(leaked)»") },
                "no report names «\(leaked)»: \(Self.descriptions(of: issues))"
            )
        }
    }

    /// A screen that renders its copy is not a leak, whatever the guard was
    /// handed. Without this, a guard that failed unconditionally would satisfy
    /// every other test here — they all expect a failure.
    func testKeyLeakGuardStaysQuietWhenTheWordsRendered() {
        assertNoKeysLeaked([Self.volumeKey, Self.soundKey], in: ["Громкость", "ЗВУК"])
    }

    /// Runs the guard over `rendered` and hands back the issues it recorded,
    /// absorbing them so the self-test itself stays green.
    ///
    /// Counting needs a matcher that accumulates instead of one that answers a
    /// single yes/no, so this is the second of the two shapes XCTest offers:
    /// the matcher goes inside `XCTExpectedFailure.Options`. The other shape —
    /// `strict:` plus a trailing `issueMatcher:`, used by
    /// `testKeyLeakGuardCatchesLowerAndUpperCasedKeys` — cannot be combined
    /// with `options:`; that overload does not exist
    /// (`XCTest.swiftmodule/arm64-apple-ios-simulator.swiftinterface:100-118`),
    /// and reaching for it is what broke the whole test target's build once.
    private static func issuesRecordedByGuard(over rendered: [String], keys: [String]) -> [XCTIssue] {
        var recorded: [XCTIssue] = []
        let options = XCTExpectedFailure.Options()
        // Strict, for the same reason: a guard that recorded nothing has to be a failure
        // rather than a quiet zero-count pass.
        options.isStrict = true
        options.issueMatcher = { issue in
            recorded.append(issue)
            return true
        }
        XCTExpectFailure("the guard has to report the leaked key", options: options) {
            assertNoKeysLeaked(keys, in: rendered)
        }
        return recorded
    }

    private static func descriptions(of issues: [XCTIssue]) -> String {
        issues.isEmpty ? "nothing" : issues.map(\.compactDescription).joined(separator: " | ")
    }
}
