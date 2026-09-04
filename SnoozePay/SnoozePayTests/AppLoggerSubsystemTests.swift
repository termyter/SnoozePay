import XCTest
@testable import SnoozePay

/// Pins the `os_log` subsystem to the identifier the app actually ships under
/// (#670).
///
/// The subsystem is what a support ticket is followed by: `log show --predicate
/// 'subsystem == "…"'` is how an error ID like `STATS-348-LEDGER-PARTIAL` gets
/// turned back into the branch that produced it. Nothing in the app reads the
/// string back, so when it drifted away from the bundle identifier in #475/#476
/// every filter written against it quietly matched zero lines, and the whole
/// target stayed green for a week.
///
/// ⚠️ These tests read `Bundle.main`, and under XCTest that is the TEST HOST,
/// not the test bundle: `SnoozePayTests` is injected into `SnoozePay.app`, so
/// `Bundle.main.bundleIdentifier` is the APP's `io.mobilife.SnoozePay` and not
/// this target's `Ivan-Emelyanov.SnoozePayTests`. That is the whole reason the
/// comparison below means anything — and the reason
/// ``testTheseTestsRunInsideTheAppProcess`` exists to say so out loud rather
/// than assume it.
final class AppLoggerSubsystemTests: XCTestCase {

    /// The identifier the app has shipped under since #475/#476, spelled out
    /// here and nowhere else in this file.
    ///
    /// A literal in a test that pins a literal in the source would only assert
    /// that two copies of one string agree. This one is compared against
    /// `Bundle.main`, i.e. against the value `project.pbxproj` actually builds
    /// with — which is a no-touch setting this suite reads and never writes.
    private static let appBundleID = "io.mobilife.SnoozePay"

    // MARK: - The premise

    /// Not the assertion — the thing the other two assertions stand on.
    ///
    /// `TEST_HOST` is what makes `Bundle.main` the app here. Dropping it is a
    /// live idea — per CLAUDE.md it is the only way to get the `Unit tests` job
    /// under ~200 s — so it is worth writing down what actually happens that
    /// day, rather than what one would guess:
    ///
    /// - this test goes RED: `Bundle.main` is the runner, not the app;
    /// - ``testTheFallbackLiteralStillSpellsTheAppsBundleIdentifier`` goes RED
    ///   too, comparing the literal against the runner's identifier;
    /// - ``testSubsystemFollowsTheRunningBundleIdentifier`` stays GREEN, because
    ///   ``AppLogger/subsystem`` resolves in whatever process runs it, so both
    ///   sides of that assertion move together.
    ///
    /// Two reds, one cause. This test's message names it, so the cheap reading
    /// of the failure — «the logging tests broke» — is contradicted on screen.
    func testTheseTestsRunInsideTheAppProcess() {
        XCTAssertEqual(
            Bundle.main.bundleIdentifier, Self.appBundleID,
            """
            Bundle.main is «\(Bundle.main.bundleIdentifier ?? "nil")», not the app. \
            Either the app's PRODUCT_BUNDLE_IDENTIFIER changed — update AppLogger.fallbackSubsystem \
            and appBundleID here — or TEST_HOST was removed and these tests no longer see the app.
            """
        )
    }

    // MARK: - The subsystem

    /// The subsystem must be READ from the running bundle, not spelled out.
    ///
    /// ⚠️ What this can catch is narrow, and worth stating: with
    /// `subsystem = Bundle.main.bundleIdentifier ?? …` in place it cannot fail,
    /// because both sides evaluate the same expression. It fails when somebody
    /// puts a literal back — which is exactly the shape the code had before
    /// #670, and exactly the shape that went stale. The drift itself is caught
    /// one test down.
    func testSubsystemFollowsTheRunningBundleIdentifier() {
        XCTAssertEqual(
            AppLogger.subsystem, Bundle.main.bundleIdentifier,
            "the subsystem is «\(AppLogger.subsystem)» while the app runs as "
                + "«\(Bundle.main.bundleIdentifier ?? "nil")» — a log filter built from one finds nothing"
        )
    }

    /// The `??` arm is a literal, so it is the part of ``AppLogger`` that can go
    /// stale again the way #670 did. It is not the only red a bundle-identifier
    /// change produces: ``testTheseTestsRunInsideTheAppProcess`` pins the same
    /// string against the same source and reddens with it. Two failures, one
    /// edit — the message on each says which literal to move.
    ///
    /// The fallback is unreachable in the app and in this target (both have a
    /// `CFBundleIdentifier`), so nothing else would ever notice it rotting. It
    /// is still the value a bundle-less host — a command-line tool linking the
    /// module — would log under, and «wrong subsystem» there costs the same
    /// grep it cost here.
    func testTheFallbackLiteralStillSpellsTheAppsBundleIdentifier() {
        XCTAssertEqual(
            AppLogger.fallbackSubsystem, Bundle.main.bundleIdentifier,
            "AppLogger.fallbackSubsystem is «\(AppLogger.fallbackSubsystem)» but the app now builds as "
                + "«\(Bundle.main.bundleIdentifier ?? "nil")»; the bundle identifier moved and the literal did not"
        )
    }
}
